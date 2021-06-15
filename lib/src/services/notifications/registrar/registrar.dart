import 'package:flutter/foundation.dart';
import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/config/notifications.dart';
import 'package:twilio_conversations/src/enum/notification/channel_type.dart';
import 'package:twilio_conversations/src/services/notifications/connector/connector.dart';
import 'package:twilio_conversations/src/services/websocket/client.dart';

import '../connector/registrar_connector.dart';
import '../connector/twilsock_connector.dart';

/// Provides an interface to the ERS registrar
class Registrar extends Stendo {
  /// Creates the new instance of registrar client
  Registrar(String productId, transport, TwilsockClient twilsock, this.config)
      : super() {
    final platform = detectPlatform();
    connectors[NotificationChannelType.gcm] = RegistrarConnector(
        channelType: NotificationChannelType.gcm,
        context: {
          'protocolVersion': 3,
          'productId': productId,
          'platform': platform
        },
        transport: transport,
        config: config);
    connectors[NotificationChannelType.fcm] = RegistrarConnector(
        channelType: NotificationChannelType.fcm,
        context: {
          'protocolVersion': 3,
          'productId': productId,
          'platform': platform
        },
        transport: transport,
        config: config);
    connectors[NotificationChannelType.apn] = RegistrarConnector(
        channelType: NotificationChannelType.apn,
        context: {
          'protocolVersion': 4,
          'productId': productId,
          'platform': platform
        },
        transport: transport,
        config: config);
    connectors[NotificationChannelType.twilsock] = TwilsockConnector(
        context: {'productId': productId, 'platform': platform},
        twilsock: twilsock,
        config: config);
    connectors[NotificationChannelType.twilsock].on(
        'transportReady', (state) => emit('transportReady', payload: state));
  }
  final NotificationsConfiguration config;
  final Map<NotificationChannelType, Connector> connectors = {};

  ///  Sets notification ID.
  ///  If new URI is different from previous, it triggers updating of registration for given channel
  ///
  ///  @param {ChannelType} channelType channel type (apn|gcm|fcm|twilsock)
  ///  @param {String} notificationId The notification ID
  void setNotificationId(
      NotificationChannelType channelType, String notificationId) {
    connector(channelType).notificationId = notificationId;
  }

  /// Subscribe for given type of message
  ///
  /// @param {String} messageType Message type identifier
  /// @param {ChannelType} channelType Channel type, can be 'twilsock', 'gcm' or 'fcm'
  /// @public
  Future<void> subscribe(
      String messageType, NotificationChannelType channelType) async {
    return await connector(channelType).subscribe(messageType);
  }

  /// Remove subscription
  /// @param {String} messageType Message type
  /// @param {String} channelType Channel type (twilsock or gcm/fcm)
  Future<void> unsubscribe(
      String messageType, NotificationChannelType channelType) async {
    return await connector(channelType).unsubscribe(messageType);
  }

  void updateToken(String token) {
    connectors.values.forEach((connector) => connector.updateToken(token));
  }

  /// @param {String} type Channel type
  /// @throws {Error} Error with description
  Connector connector(NotificationChannelType type) {
    final connector = connectors[type];
    if (connector == null) {
      throw Exception('Unknown channel type: $type');
    }
    return connector;
  }

  /// Returns platform String limited to max 128 chars
  String detectPlatform() {
    return '${kIsWeb ? 'Flutter Web' : 'DartVM (Flutter)'}';
  }
}
