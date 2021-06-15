import 'dart:async';

import 'package:twilio_conversations/src/errors/twilsockerror.dart';

class RequestDescriptor {
  RequestDescriptor(
      {this.id,
      this.resolve,
      this.reject,
      this.timeoutCallback,
      this.message,
      int timeout,
      String errorMessage}) {
    _timer = Timer(Duration(milliseconds: timeout), () {
      reject(TwilsockError(errorMessage));
      timeoutCallback?.call();
      _alreadyRejected = true;
    });
  }
  final Map<String, dynamic> message;
  final String id;
  final Function resolve;
  final Function reject;
  final Function timeoutCallback;
  bool _alreadyRejected = false;
  bool get alreadyRejected => _alreadyRejected;
  Timer _timer;
  Timer get timeout => _timer;
}
