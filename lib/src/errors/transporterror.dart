import 'package:dio/dio.dart';

class TransportError extends Error {
  TransportError(
      {this.message, this.code, this.body, this.status, this.headers});

  final String message;
  final int code;
  final Map<String, dynamic> body;
  final String status;
  final Headers headers;

  @override
  String toString() {
    return 'TransportError: $message';
  }
}
