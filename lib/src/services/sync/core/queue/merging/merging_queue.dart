import 'dart:async';

import 'package:twilio_conversations/src/services/sync/core/queue/models/request.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/typedef/input_reducer.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/typedef/request_function.dart';

class MergingQueue<InputType, ReturnType> {
  MergingQueue(this.inputMergingFunction);
  List<QueuedRequest> queuedRequests = [];
  bool isRequestInFlight = false;
  InputReducer inputMergingFunction;

  Future add(
      InputType input, RequestFunction<InputType, ReturnType> requestFunction) {
    final completer = Completer<ReturnType>();
    queuedRequests.add(QueuedRequest<InputType, ReturnType>(
        input: input, requestFunction: requestFunction, completer: completer));
    wakeupQueue();
    return completer.future;
  }

  Future squashAndAdd(
      InputType input, RequestFunction<InputType, ReturnType> requestFunction) {
    final queueToSquash = queuedRequests;
    queuedRequests.clear();
    var reducedInput;
    if (queueToSquash.isNotEmpty) {
      reducedInput =
          queueToSquash.map((r) => r.input).reduce(inputMergingFunction);

      reducedInput = inputMergingFunction(reducedInput, input);
    } else {
      reducedInput = input;
    }
    final promise = add(reducedInput, requestFunction);
    queueToSquash.forEach((request) => request.completer.complete());
    return promise;
  }

  bool isEmpty() {
    return queuedRequests.isEmpty && !isRequestInFlight;
  }

  void wakeupQueue() async {
    if (queuedRequests.isEmpty || isRequestInFlight) {
      return;
    } else {
      final requestToExecute = queuedRequests.removeAt(0);
      isRequestInFlight = true;
      await requestToExecute.requestFunction(requestToExecute.input);
      requestToExecute.completer.complete();

      isRequestInFlight = false;
      wakeupQueue();
    }
  }
}
