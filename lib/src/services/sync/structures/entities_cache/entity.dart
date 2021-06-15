import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/enum/sync/subscribtion_state.dart';
import 'package:twilio_conversations/src/services/sync/core/closable.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/core/router.dart';
import 'package:twilio_conversations/src/services/sync/removal_handler/removal_handler.dart';

abstract class SyncEntity {
  SyncEntity(this.removalHandler,
      {SyncNetwork network, SyncRouter router, Storage storage})
      : _network = network,
        _router = router,
        _storage = storage;

  RemovalHandler removalHandler;
  final SyncNetwork _network;
  final Storage _storage;
  final SyncRouter _router;

  SyncSubscriptionState subscriptionState = SyncSubscriptionState.none;
  final Map<String, Closeable> _attachedListeners = {};
  String get sid;
  String get uniqueName;
  String get type => 'sync_entity';
  int get lastEventId;
  String get indexName;
  String get queryString;

  void advanceLastEventId(int eventId, {String revision});

  void update(Map<String, dynamic> update, {bool isStrictlyOrdered});

  void onRemoved(bool locally);

  void reportFailure(err) {
    if (err.status == 404) {
      // assume that 404 means that entity has been removed while we were away
      onRemoved(false);
    } else {
      broadcastEventToListeners('failure', err);
    }
  }

  /// Subscribe to changes of data entity
  /// @private
  void subscribe() {
    _router.subscribe(sid, this);
  }

  /// Unsubscribe from changes of current data entity
  /// @private
  void unsubscribe() {
    _router.unsubscribe(sid);
  }

  void setSubscriptionState(SyncSubscriptionState newState) {
    subscriptionState = newState;
    broadcastEventToListeners('_subscriptionStateChanged', newState);
  }

  /// @public
  void close() {
    unsubscribe();
    if (removalHandler != null) {
      removalHandler(type, sid, uniqueName);
    }
  }

  void attach(Closeable closeable) {
    final uuid = closeable.listenerUuid;
    final existingRecord = _attachedListeners[uuid];
    if (existingRecord != null) {
      return;
    }
    if (_attachedListeners.isEmpty) {
      // the first one to arrive
      subscribe();
    }
    _attachedListeners[uuid] = closeable;
  }

  void detach(String listenerUuid) {
    _attachedListeners.remove(listenerUuid);
    if (_attachedListeners.isEmpty) {
      // last one out, turn off lights, shut the door
      close(); // invokes unsubscribe and removal handler
    }
  }

  void broadcastEventToListeners(String eventName, args) {
    for (final listener in _attachedListeners.values) {
      listener.emit(eventName, payload: args);
    }
  }
}
