import 'dart:async';

import 'package:twilio_conversations/src/services/sync/core/queue/typedef/request_function.dart';

class QueuedRequest<InputType, ReturnType> {
  QueuedRequest({this.input, this.requestFunction, this.completer});
  InputType input;
  RequestFunction<InputType, ReturnType> requestFunction;
  Completer completer;
}
