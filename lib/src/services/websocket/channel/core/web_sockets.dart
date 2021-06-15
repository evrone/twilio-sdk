import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'base.dart' as stab;

class WebSocket implements stab.WebSocket {
  html.WebSocket _socket;
  final StreamController _controller = StreamController();

  WebSocket._(this._socket) : done = _socket.onClose.first {
    _controller.stream.listen(
      (data) => _send(data),
      onError: (error) => _send(error.toString()),
    );
    _socket.onOpen.listen((event) {
      onOpen?.call();
    });
    _socket.onClose.listen((html.CloseEvent event) {
      closeCode = event.code;
      closeReason = event.reason;
      _streamController.close();
      onClose?.call(event.reason);
    });
    _socket.onError.listen((html.Event error) {
      _streamController.addError(error);
      onError?.call(error);
    });
    _socket.onMessage.listen((html.MessageEvent message) async {
      final data = message.data;
      onMessage?.call();
      if (data is String) {
        _streamController.add(data);
        return;
      }
      if (data is html.Blob) {
        final reader = html.FileReader();
        reader.readAsArrayBuffer(data);
        await reader.onLoad.first;
        _streamController.add(reader.result);
        return;
      }

      throw UnsupportedError('unspported data type $data');
    });
  }

  static Future<WebSocket> connect(
    String url, {
    Iterable<String> protocols,
  }) async {
    final s = html.WebSocket(url, protocols);
    await s.onOpen.first;
    return WebSocket._(s);
  }

  void _send(data) {
    if (data is String) {
      return _socket.send(data);
    }
    if (data is List<int>) {
      return _socket.sendByteBuffer(Uint8List.fromList(data).buffer);
    }

    throw UnsupportedError('unspported data type $data');
  }

  @override
  void add(data) => _controller.add(data);

  @override
  Future addStream(Stream stream) => _controller.addStream(stream);

  @override
  void addUtf8Text(List<int> bytes) => _controller.add(utf8.decode(bytes));

  @override
  Future close([int code, String reason]) {
    _controller.close();
    if (code != null) {
      _socket.close(code, reason);
    } else {
      _socket.close();
    }
    return done;
  }

  @override
  int closeCode;

  @override
  String closeReason;

  @override
  String get extensions => _socket.extensions;

  @override
  String get protocol => _socket.protocol;

  @override
  int get readyState => _socket.readyState;

  @override
  final Future done;

  final StreamController<dynamic> _streamController = StreamController();

  @override
  String get binaryType => _socket.binaryType;

  @override
  Function(dynamic) onClose;

  @override
  Function(dynamic) onError;

  @override
  Function onMessage;

  @override
  Function onOpen;

  @override
  set binaryType(String _binaryType) {
    _socket.binaryType = _binaryType;
  }
}
