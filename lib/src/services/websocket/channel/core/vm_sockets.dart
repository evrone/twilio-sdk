import 'dart:async';
import 'dart:io' as io;

import 'package:jotaro/jotaro.dart';

import 'base.dart' as stab;

class WebSocket extends Stendo implements stab.WebSocket {
  final io.WebSocket _socket;

  WebSocket._(this._socket) {
    on('open', (_) {
      onOpen?.call();
    });
    on('message', (_) {
      onMessage?.call();
    });
    on('error', (e) {
      onError?.call(e);
    });
    on('closed', (e) {
      onClose?.call(e);
    });
  }

  @override
  String binaryType;

  Future<WebSocket> connect(
    String url, {
    Iterable<String> protocols,
  }) async {
    final socket = await io.WebSocket.connect(url, protocols: protocols);
    socket.listen((event) async {
      if ((await socket.length) == 1) {
        emit('open', payload: event);
      }
      emit('message', payload: event);
    }, onError: (error) {
      emit('error', payload: error);
    }, onDone: () {
      emit('closed', payload: socket.closeReason);
    });
    return WebSocket._(socket);
  }

  @override
  Function onOpen;
  @override
  Function onMessage;
  @override
  Function(dynamic) onError;
  @override
  Function(dynamic) onClose;

  @override
  void add(data) => _socket.add(data);

  @override
  Future addStream(Stream stream) => _socket.addStream(stream);

  @override
  void addUtf8Text(List<int> bytes) => _socket.addUtf8Text(bytes);

  @override
  Future close([int code, String reason]) => _socket.close(code, reason);

  @override
  int get closeCode => _socket.closeCode;

  @override
  String get closeReason => _socket.closeReason;

  @override
  String get extensions => _socket.extensions;

  @override
  String get protocol => _socket.protocol;

  @override
  int get readyState => _socket.readyState;

  @override
  Future get done => _socket.done;
}
