import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';

import 'configuration.dart';

abstract class Network {
  Network(this.transport, this.config);
  final transport;
  final Configuration config;

  Future<Response> get(String uri);
  Future<Response> post(String uri,
      {Map<String, dynamic> body,
      dynamic media,
      String contentType,
      String revision,
      bool retryWhenThrottled});
  Future<Response> put(String uri, Map<String, dynamic> body,
      {String revision});
  Future<Response> delete(String uri);

  Future executeWithRetry(Function request, {bool retryWhenThrottled});

  BackoffRetrierConfig _backoffConfig();
}
