import 'dart:async';
import 'dart:typed_data';

final _unsupportedError = UnsupportedError(
    'Cannot work with WebSocket without dart:html or dart:io.');

class WebSocket implements StreamConsumer<dynamic /*String|List<int>*/ > {
  static Future<WebSocket> connect(
    String url, {
    Iterable<String> protocols,
  }) async =>
      throw _unsupportedError;

  void add(ByteBuffer data) => throw _unsupportedError;

  String binaryType;

  Function onOpen;
  Function onMessage;
  Function(dynamic) onError;
  Function(dynamic) onClose;

  @override
  Future addStream(Stream stream) => throw _unsupportedError;

  void addUtf8Text(List<int> bytes) => throw _unsupportedError;

  @override
  Future close([int code, String reason]) => throw _unsupportedError;

  int get closeCode => throw _unsupportedError;

  String get closeReason => throw _unsupportedError;

  String get extensions => throw _unsupportedError;

  String get protocol => throw _unsupportedError;

  int get readyState => throw _unsupportedError;

  Future get done => throw _unsupportedError;
}
