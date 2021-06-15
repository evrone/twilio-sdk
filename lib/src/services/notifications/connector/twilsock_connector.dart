import 'package:twilio_conversations/src/config/notifications.dart';
import 'package:twilio_conversations/src/enum/notification/update_reason.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/services/notifications/models/registration_state.dart';
import 'package:twilio_conversations/src/services/websocket/client.dart';
import 'package:uuid/uuid.dart';

import 'connector.dart';

const DEFAULT_TTL = 60 * 60 * 48;

/// Registrar connector implementation for twilsock
class TwilsockConnector extends Connector {
  TwilsockConnector(
      {this.context, this.twilsock, NotificationsConfiguration config})
      : super(config) {
    context['id'] = Uuid().v4();
    twilsock.on('stateChanged', (state) {
      if (state != TwilsockState.connected) {
        emit('transportReady', payload: false);
      }
    });
    twilsock.on('registered', (id) {
      if (context != null &&
          id == context['id'] &&
          twilsock.state == TwilsockState.connected) {
        emit('transportReady', payload: true);
      }
    });
  }

  final Map<String, dynamic> context;
  TwilsockClient twilsock;

  //setNotificationId(...args) { }
  @override
  void updateToken(token) {
    // no need to do anything here, twilsock backend handles it on it's own
    // so just ignoring here
  }
  void updateContextRequest(messageTypes) {
    final context = {
      'product_id': this.context['productId'],
      'notification_protocol_version': 4,
      'endpoint_platform': this.context['platform'],
      'message_types': messageTypes
    };
    emit('transportReady', payload: false);
    twilsock.setNotificationsContext(context['id'], context);
  }

  @override
  Future<RegistrationState> updateRegistration(registration, reasons) async {
    if (!reasons.contains(NotificationUpdateReason.messageType)) {
      return null;
    }
    updateContextRequest(List.from(registration.messageTypes));
    return registration;
  }

  @override
  void removeRegistration() {
    twilsock.removeNotificationsContext(context['id']);
  }
}
