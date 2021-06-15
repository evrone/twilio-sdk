import 'dart:async';

import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/abstract_classes/network.dart';
import 'package:twilio_conversations/src/config/conversations.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/retrier.dart';

import 'session/session.dart';

class ConversationNetwork implements Network {
  @override
  ConversationsConfiguration config;
  Session session;
  @override
  var transport;

  int cacheLifetime;
  Map<String, dynamic> cache;
  Timer timer;
  ConversationNetwork(config, {this.session, this.transport}) {
    initCacheLifetime();
  }

  void initCacheLifetime() async {
    cacheLifetime = 0;
    final seconds = (await session.getHttpCacheInterval()).round();
    cacheLifetime = seconds * 1000;
    cleanupCache();
  }

  BackoffRetrierConfig _backoffConfig() {
    return config.backoffConfigDefault.clone(
        min: config.backoffConfigOverride.min,
        max: config.backoffConfigOverride.max,
        maxAttemptsTime: config.backoffConfigOverride.maxAttemptsTime,
        maxAttemptsCount: config.backoffConfigOverride.maxAttemptsCount,
        initial: config.backoffConfigOverride.initial,
        randomness: config.backoffConfigOverride.randomness);
  }

  bool retryWhenThrottled() {
    if (config.retryWhenThrottledOverride != null) {
      return config.retryWhenThrottledOverride;
    }
    if (config.retryWhenThrottledDefault != null) {
      return config.retryWhenThrottledDefault;
    }
    return false;
  }

  bool isExpired(DateTime timestamp) {
    return cacheLifetime == null ||
        (DateTime.now().difference(timestamp)).inMilliseconds > cacheLifetime;
  }

  void cleanupCache() {
    for (var k in cache.keys) {
      if (isExpired(cache[k].timestamp)) {
        cache.remove(k);
      }
    }
    if (cache.isEmpty) {
      timer.cancel();
      timer = null;
    }
  }

  void pokeTimer() {
    timer ??= Timer.periodic(
        Duration(milliseconds: cacheLifetime * 2), (timer) => cleanupCache());
  }

  @override
  Future executeWithRetry(Function request, {bool retryWhenThrottled = true}) {
    final completer = Completer();
    final codesToRetryOn = [502, 503, 504];
    if (retryWhenThrottled) {
      codesToRetryOn.add(429);
    }
    final backoffConfig = _backoffConfig();
    final retrier = Retrier(
        minDelay: backoffConfig.min,
        maxDelay: backoffConfig.max,
        randomness: backoffConfig.randomness,
        maxAttemptsTime: backoffConfig.maxAttemptsTime,
        maxAttemptsCount: backoffConfig.maxAttemptsCount); //  );
    retrier.on('attempt', (retr) async {
      var result;
      try {
        result = request();
      } catch (err) {
        if (codesToRetryOn.contains(err.status)) {
          final delayOverride =
              int.tryParse(err.headers ? err.headers['Retry-After'] : null);
          retr.failed(err,
              nextAttemptDelayOverride:
                  delayOverride == null ? null : delayOverride * 1000);
        } else if (err.message == 'Twilsock disconnected') {
          // Ugly hack. We must make a proper exceptions for twilsock
          retr.failed(err);
        } else {
          // Fatal error
          retr.removeAllListeners();
          retr.cancel();
          completer.completeError(err);
        }
      }
      retr.succeeded(result);
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
    final cacheEntry = cache[url];
    if (cacheEntry != null && !isExpired(cacheEntry.timestamp)) {
      return cacheEntry.response;
    }
    final headers = {};
    final response = await executeWithRetry(
        () => transport.get(url, headers, config.productId),
        retryWhenThrottled: retryWhenThrottled());
    cache[url] = {'response': response, 'timestamp': DateTime.now()};
    pokeTimer();
    return response;
  }

  @override
  Future<Response> delete(String uri) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<Response> post(String uri,
      {Map<String, dynamic> body,
      dynamic media,
      String contentType,
      String revision,
      bool retryWhenThrottled}) {
    // TODO: implement post
    throw UnimplementedError();
  }

  @override
  Future<Response> put(String uri, Map<String, dynamic> body,
      {String revision}) {
    // TODO: implement put
    throw UnimplementedError();
  }
}
