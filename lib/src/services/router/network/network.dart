import 'dart:async';

import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/abstract_classes/network.dart';
import 'package:twilio_conversations/src/config/mcs_client.dart';
import 'package:twilio_conversations/src/services/router/network/transport.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/retrier.dart';

class McsNetwork implements Network {
  McsNetwork(this.config, this.transport);

  @override
  McsConfiguration config;
  @override
  McsTransport transport;

  BackoffRetrierConfig _backoffConfig() {
    return McsConfiguration.backoffConfigDefault.clone(
        min: config.backoffConfigOverride.min,
        max: config.backoffConfigOverride.max,
        maxAttemptsTime: config.backoffConfigOverride.maxAttemptsTime,
        maxAttemptsCount: config.backoffConfigOverride.maxAttemptsCount,
        initial: config.backoffConfigOverride.initial,
        randomness: config.backoffConfigOverride.randomness);
  }

  bool get retryWhenThrottled {
    if (config.retryWhenThrottledOverride != null) {
      return config.retryWhenThrottledOverride;
    }
    if (McsConfiguration.retryWhenThrottledDefault != null) {
      return McsConfiguration.retryWhenThrottledDefault;
    }
    return false;
  }

  @override
  Future executeWithRetry(Function request, {bool retryWhenThrottled = false}) {
    final completer = Completer();
    final codesToRetryOn = [502, 503, 504];
    if (retryWhenThrottled) {
      codesToRetryOn.add(429);
    }
    final backoffConf = _backoffConfig();
    final retrier = Retrier(minDelay: backoffConf.min);
    retrier.on('attempt', (_) {
      try {
        request().then((result) => retrier.succeeded(result));
      } catch (err) {
        if (codesToRetryOn.contains(err.status)) {
          retrier.failed(err);
        } else if (err.message == 'Twilsock disconnected') {
          // Ugly hack. We must make a proper exceptions for twilsock
          retrier.failed(err);
        } else {
          // Fatal error
          retrier.removeAllListeners();
          retrier.cancel();
          completer.completeError(err);
        }
      }
    });
    retrier.on('succeeded', (result) {
      completer.complete(result);
    });
    retrier.on('cancelled', (err) => completer.completeError(err));
    retrier.on('failed', (err) => completer.completeError(err));
    retrier.start();
    return completer.future;
  }

  @override
  Future<Response> get(String url) async {
    final headers = {'X-Twilio-Token': config.token};
    //log.trace('sending GET request to ', url, ' headers ', headers);
    final response = await executeWithRetry(() => transport.get(url, headers),
        retryWhenThrottled: retryWhenThrottled);
    //log.trace('response', response);
    return response;
  }

  @override
  Future<Response> post(String url,
      {dynamic media,
      String contentType,
      Map<String, dynamic> body,
      bool retryWhenThrottled,
      String revision}) async {
    final headers = {'X-Twilio-Token': config.token};
    if (media is! FormData && contentType != null) {
      headers['Content-Type'] = contentType;
    }
    var response;
    //log.trace('sending POST request to ', url, ' headers ', headers);
    try {
      response = await transport.post(url, headers, media);
    } catch (err) {
      if (err is TypeError) {
        //log.trace('got error in post response', err);
        throw Exception(
            'Posting FormData supported only with browser engine\'s FormData');
      } else {
        rethrow;
      }
    }
    //log.trace('response', response);
    return response;
  }

  @override
  Future<Response> delete(String uri) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<Response> put(String uri, Map<String, dynamic> body,
      {String revision}) {
    // TODO: implement put
    throw UnimplementedError();
  }
}
