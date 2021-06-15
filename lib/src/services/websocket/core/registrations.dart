import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/enum/twilsock/method.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/notificationUpdate.dart';
import 'package:uuid/uuid.dart';

import 'packet_interface.dart';

class Registrations extends Stendo {
  PacketInterface transport;
  Map<String, Map<String, dynamic>> registrations = {};
  Map<String, Set> registrationsInProgress = {};
  Registrations(this.transport);
  void putNotificationContext(
      String contextId, Map<String, dynamic> context) async {
    final header = NotificationContextUpdate(
        method: Method.put_notification_ctx, notificationCtxId: contextId);
    await transport.sendWithReply(header, payload: context);
  }

  Future<void> deleteNotificationContext(String contextId) async {
    final message = NotificationContextUpdate(
        method: Method.delete_notification_ctx, notificationCtxId: contextId);
    await transport.sendWithReply(message);
  }

  void updateRegistration(
      String contextId, Map<String, dynamic> context) async {
    // ('update registration for context', contextId);
    var registrationAttempts = registrationsInProgress[contextId];
    if (registrationAttempts == null) {
      registrationAttempts = <String>{};
      registrationsInProgress[contextId] = registrationAttempts;
    }
    final attemptId = Uuid().v4();
    registrationAttempts.add(attemptId);
    try {
      putNotificationContext(contextId, context);
      //('registration attempt succeeded for context', context);
      registrationAttempts.remove(attemptId);
      if (registrationAttempts.isEmpty) {
        registrationsInProgress.remove(contextId);
        emit('registered', payload: contextId);
      }
    } catch (err) {
      //logger_1.log.warn('registration attempt failed for context', context);
      //logger_1.log.debug(err);
      registrationAttempts.remove(attemptId);
      if (registrationAttempts.isEmpty) {
        registrationsInProgress.remove(contextId);
        emit('registrationFailed',
            payload: {'contextId': contextId, 'error': err});
      }
    }
  }

  void updateRegistrations() {
    //logger_1.log.trace(`refreshing ${this.registrations.size} registrations`);
    registrations.forEach((id, context) {
      updateRegistration(id, context);
    });
  }

  void setNotificationsContext(String contextId, Map<String, dynamic> context) {
    registrations[contextId] = context;
    if (transport.isConnected) {
      updateRegistration(contextId, context);
    }
  }

  void removeNotificationsContext(String contextId) async {
    if (!registrations.containsKey(contextId)) {
      return;
    }
    await deleteNotificationContext(contextId);
    if (transport.isConnected) {
      registrations.remove(contextId);
    }
  }
}
