import 'package:twilio_conversations/src/errors/syncerror.dart';

import '../entity.dart';

/// A data container used by the Subscriptions class to track subscribed entities' local
/// representations and their state.
class SubscribedEntity {
  SubscribedEntity(this.localObject);
  SyncEntity localObject;
  var pendingCorrelationId;
  var pendingAction;
  bool established = false;
  int retryCount = 0;
  var rejectedWithError;

  String get sid => localObject.sid;

  String get type => localObject.type;

  int get lastEventId => localObject.lastEventId;

  // below properties are specific to Insights only
  String get indexName => localObject.indexName;

  String get queryString => localObject.queryString;

  bool get isEstablished => established;

  void update(Map<String, dynamic> event, bool isStrictlyOrdered) {
    localObject.update(event, isStrictlyOrdered: isStrictlyOrdered);
  }

  void updatePending(action, correlationId) {
    pendingAction = action;
    pendingCorrelationId = correlationId;
  }

  void reset() {
    updatePending(null, null);
    retryCount = 0;
    established = false;
    setSubscriptionState('none');
  }

  void markAsFailed(message) {
    rejectedWithError = message.error;
    updatePending(null, null);
    localObject.reportFailure(SyncError(
        'Failed to subscribe on service events: ${message.error.message}',
        status: message.error.status,
        code: message.error.code));
  }

  void complete(int eventId) {
    updatePending(null, null);
    established = true;
    localObject.advanceLastEventId(eventId);
  }

  void setSubscriptionState(newState) {
    localObject.setSubscriptionState(newState);
  }
}
