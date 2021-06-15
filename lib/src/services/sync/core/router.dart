import 'package:twilio_conversations/src/config/sync.dart';
import 'package:twilio_conversations/src/services/notifications/client.dart';

import 'subscriptions.dart';

const SYNC_DOCUMENT_NOTIFICATION_TYPE = 'com.twilio.rtd.cds.document';
const SYNC_LIST_NOTIFICATION_TYPE = 'com.twilio.rtd.cds.list';
const SYNC_MAP_NOTIFICATION_TYPE = 'com.twilio.rtd.cds.map';
const SYNC_NOTIFICATION_TYPE = 'twilio.sync.event';

/// @class Router
/// @classdesc Routes all incoming messages to the consumers
class SyncRouter {
  SyncRouter({this.config, this.subscriptions, this.notifications}) {
    notifications.subscribe(SYNC_NOTIFICATION_TYPE);
    notifications.subscribe(SYNC_DOCUMENT_NOTIFICATION_TYPE);
    notifications.subscribe(SYNC_LIST_NOTIFICATION_TYPE);
    notifications.subscribe(SYNC_MAP_NOTIFICATION_TYPE);
    notifications.on('message',
        (payload) => onMessage(payload['messageType'], payload['payload']));
    notifications.on('transportReady',
        (isConnected) => onConnectionStateChanged(isConnected));
  }

  SyncConfiguration config;
  Subscriptions subscriptions;
  NotificationsClient notifications;

  /// Entry point for all incoming messages
  /// @param {String} type - Type of incoming message
  /// @param {Object} message - Message to route
  void onMessage(String type, message) {
    //('Notification type:', type, 'content:', message);
    switch (type) {
      case SYNC_DOCUMENT_NOTIFICATION_TYPE:
      case SYNC_LIST_NOTIFICATION_TYPE:
      case SYNC_MAP_NOTIFICATION_TYPE:
        subscriptions.acceptMessage(message, false);
        break;
      case SYNC_NOTIFICATION_TYPE:
        subscriptions.acceptMessage(message, true);
        break;
    }
  }

  /// Subscribe for events
  void subscribe(String sid, entity) {
    subscriptions.add(sid, entity);
  }

  /// Unsubscribe from events
  void unsubscribe(String sid) {
    subscriptions.remove(sid);
  }

  /// Handle transport establishing event
  /// If we have any subscriptions - we should check object for modifications
  void onConnectionStateChanged(bool isConnected) {
    subscriptions.onConnectionStateChanged(isConnected);
  }
}
