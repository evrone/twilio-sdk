import 'package:twilio_conversations/src/services/sync/core/queue/merging/merging_queue.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/typedef/input_reducer.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/typedef/request_function.dart';

class NamespacedMergingQueue<K, InputType, ReturnType> {
  NamespacedMergingQueue(this.inputReducer);

  Map<K, MergingQueue> queueByNamespaceKey = {};
  InputReducer inputReducer;

  Future<ReturnType> add(K namespaceKey, InputType input,
      RequestFunction<InputType, ReturnType> requestFunction) {
    return invokeQueueMethod(
        namespaceKey, (queue) => queue.add(input, requestFunction));
  }

  Future<ReturnType> squashAndAdd(K namespaceKey, InputType input,
      RequestFunction<InputType, ReturnType> requestFunction) {
    return invokeQueueMethod(
        namespaceKey, (queue) => queue.squashAndAdd(input, requestFunction));
  }

  Future<ReturnType> invokeQueueMethod(K namespaceKey, queueMethodInvoker) {
    if (!queueByNamespaceKey.containsKey(namespaceKey)) {
      queueByNamespaceKey[namespaceKey] = MergingQueue(inputReducer);
    }
    final queue = queueByNamespaceKey[namespaceKey];
    final result = queueMethodInvoker(queue);
    if (queueByNamespaceKey[namespaceKey].isEmpty()) {
      queueByNamespaceKey.remove(namespaceKey);
    }
    return result;
  }
}
