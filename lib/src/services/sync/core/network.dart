import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/abstract_classes/network.dart';
import 'package:twilio_conversations/src/config/client_info.dart';
import 'package:twilio_conversations/src/config/sync.dart';
import 'package:twilio_conversations/src/errors/syncerror.dart';
import 'package:twilio_conversations/src/errors/transportunavailableerror.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/retrier.dart';
import 'package:uuid/uuid.dart';

const int MINIMUM_RETRY_DELAY = 4000;
const int MAXIMUM_RETRY_DELAY = 60000;
const int MAXIMUM_ATTEMPTS_TIME = 90000;
const double RETRY_DELAY_RANDOMNESS = 0.2;
String messageFromErrorBody(transportError) {
  if (transportError.body) {
    if (transportError.body.message) {
      return transportError.body.message;
    }
  }
  switch (transportError.status) {
    case 429:
      return 'Throttled by server';
    case 404:
      return 'Not found from server';
    default:
      return 'Error from server';
  }
}

int codeFromErrorBody(Error transportError) {
  if ((transportError as dynamic).body != null) {
    return (transportError as dynamic).body.code;
  }
  return 0;
}

Error mapTransportError(transportError) {
  if (transportError.status == 409) {
    return SyncNetworkError(
        messageFromErrorBody(transportError), transportError.body,
        status: transportError.status, code: codeFromErrorBody(transportError));
  } else if (transportError.status) {
    return SyncError(messageFromErrorBody(transportError),
        status: transportError.status, code: codeFromErrorBody(transportError));
  } else if (transportError is TransportUnavailableError) {
    return transportError;
  } else {
    return SyncError(transportError.message, status: 0, code: 0);
  }
}

/// @classdesc Incapsulates network operations to make it possible to add some optimization/caching strategies
class SyncNetwork implements Network {
  SyncNetwork(this.clientInfo, this.config, this.transport);

  final ClientInfo clientInfo;
  @override
  final SyncConfiguration config;
  @override
  final transport;

  Map<String, dynamic> createHeaders() {
    return {
      'Content-Type': 'application/json',
      'Twilio-Sync-Client-Info': json.encode(clientInfo),
      'Twilio-Request-Id': 'RQ' + Uuid().v4()
        ..replaceAll('-', '')
    };
  }

  BackoffRetrierConfig _backoffConfig() {
    return BackoffRetrierConfig(
        min: config.backoffConfig.min ?? MINIMUM_RETRY_DELAY,
        max: config.backoffConfig.max ?? MAXIMUM_RETRY_DELAY,
        maxAttemptsTime:
            config.backoffConfig.maxAttemptsTime ?? MAXIMUM_ATTEMPTS_TIME,
        randomness: config.backoffConfig.randomness ?? RETRY_DELAY_RANDOMNESS);
  }

  @override
  Future executeWithRetry(Function request, {bool retryWhenThrottled = true}) {
    final completer = Completer();
    final codesToRetryOn = [502, 503, 504];
    if (retryWhenThrottled) {
      codesToRetryOn.add(429);
    }
    final backoffConf = _backoffConfig();
    final retrier = Retrier(
        minDelay: backoffConf.min,
        maxDelay: backoffConf.max,
        randomness: backoffConf.randomness,
        maxAttemptsTime: backoffConf.maxAttemptsTime,
        maxAttemptsCount: backoffConf.maxAttemptsCount); //  );
    retrier.on('attempt', (retr) async {
      var result;
      try {
        result = request();
      } catch (err) {
        if (codesToRetryOn.contains(err.status)) {
          final delayOverride =
              int.tryParse(err.headers ? err.headers['Retry-After'] : null);
          retr.failed(mapTransportError(err),
              nextAttemptDelayOverride:
                  delayOverride == null ? null : delayOverride * 1000);
        } else if (err.message == 'Twilsock disconnected') {
          // Ugly hack. We must make a proper exceptions for twilsock
          retr.failed(mapTransportError(err));
        } else {
          // Fatal error
          retr.removeAllListeners();
          retr.cancel();
          completer.completeError(mapTransportError(err));
        }
      }
      retr.succeeded(result);
    });

    retrier.on('succeeded', (result) {
      completer.complete(result);
    });
    retrier.on(
        'cancelled', (err) => completer.completeError(mapTransportError(err)));
    retrier.on(
        'failed', (err) => completer.completeError(mapTransportError(err)));
    retrier.start();
    return completer.future;
  }

  /// Make a GET request by given URI
  /// @Returns Promise<Response> Result of successful get request
  @override
  Future<Response> get(String uri) {
    final headers = createHeaders();
    //('GET', uri, 'ID:', headers['Twilio-Request-Id']);   todo
    return executeWithRetry(() => transport.get(uri, headers, config.productId),
        retryWhenThrottled: true);
  }

  @override
  Future<Response> post(String uri,
      {Map<String, dynamic> body,
      dynamic media,
      String contentType,
      String revision,
      bool retryWhenThrottled = false}) {
    final headers = createHeaders();
    if (revision != null) {
      headers['If-Match'] = revision;
    }
    //('POST', uri, 'ID:', headers['Twilio-Request-Id']);   todo
    return executeWithRetry(
        () => transport.post(uri, headers, body, config.productId),
        retryWhenThrottled: retryWhenThrottled);
  }

  @override
  Future<Response> put(String uri, Map body, {String revision}) {
    final headers = createHeaders();
    if (revision != null) {
      headers['If-Match'] = revision;
    }
    //('PUT', uri, 'ID:', headers['Twilio-Request-Id']); todo
    return executeWithRetry(
        () => transport.put(uri, headers, body, config.productId),
        retryWhenThrottled: false);
  }

  @override
  Future<Response> delete(String uri) {
    final headers = createHeaders();
    //('DELETE', uri, 'ID:', headers['Twilio-Request-Id']); todo
    return executeWithRetry(
        () => transport.delete(uri, headers, config.productId),
        retryWhenThrottled: false);
  }
}
