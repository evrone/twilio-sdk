import 'dart:typed_data';

import 'package:jotaro/jotaro.dart';

import 'core/base.dart'
    if (dart.library.io) 'dart_websockets/vm_sockets.dart'
    if (dart.library.html) 'dart_websockets/web_sockets.dart';

class WebSocketChannel extends Stendo {
  WebSocketChannel(this.url) : super();

  final String url;
  WebSocket socket;
  bool get isConnected => socket != null && socket.readyState == 1;

  void connect() async {
    //_1.log.trace('connecting to socket');
    WebSocket socket;
    try {
      socket = await WebSocket.connect(url);
    } catch (e) {
      //_1.log.debug('Socket error: ${url}');
      emit('socketError', payload: e);
      return;
    }
    socket.binaryType = 'arraybuffer';
    socket.onOpen = () {
      //_1.log.debug('socket opened ${url}');
      emit('connected');
    };
    socket.onClose = (e) {
      //_1.log.debug('socket closed', e);
      emit('disconnected', payload: e);
    };
    socket.onError = (e) {
      //_1.log.debug('Socket error:', e);
      emit('socketError', payload: e);
    };
    socket.onMessage = (message) {
      emit('message', payload: message.data);
    };
    this.socket = socket;
  }

  void send(ByteBuffer message) {
    socket.add(message);
  }

  @override
  void close() {
    //_1.log.trace('closing socket');
    if (socket != null) {
      try {
        socket.close();
      } finally {}
    }
  }
}
