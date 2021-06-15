import 'dart:async';

class Deferred<T> {
  final Completer _completer = Completer();
  T current;

  Future get promise => _completer.future;
  void update(T value) {
    _completer.complete(value);
  }

  void set(T value) {
    current = value;
    _completer.complete(value);
  }

  void fail(dynamic e) {
    _completer.completeError(e);
  }
}
