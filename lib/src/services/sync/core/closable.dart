import 'package:jotaro/jotaro.dart';
import 'package:uuid/uuid.dart';

class Closeable extends Stendo {
  Closeable() : super();

  bool closed = false;
  String uuid = Uuid().v4();

  String get listenerUuid => uuid;

  @override
  void close() {
    removeAllListeners();
    closed = true;
  }

  void ensureNotClosed() {
    if (closed) {
      throw Exception('Invalid operation on closed object');
    }
  }
}
