import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/enum/notification/channel_type.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/services/notifications/models/push_notification.dart';
import 'package:twilio_conversations/src/services/notifications/models/transport_state.dart';
import 'package:twilio_conversations/src/services/websocket/client.dart';

import '../../config/notifications.dart';
import 'registrar/registrar.dart';

/// @class
/// @alias Notifications
/// @classdesc The helper library for the notification service.
/// Provides high level api for creating and managing notification subscriptions and receiving messages
/// Creates the instance of Notification helper library
///
/// @constructor
/// @param {String} token - Twilio access token
/// @param {Notifications#ClientOptions} options - Options to customize client behavior
class NotificationsClient extends Stendo {
  NotificationsClient(String token,
      {this.minTokenRefreshInterval = 10000,
      this.productId = 'notifications',
      TwilsockClient transport,
      TwilsockClient twilsockClient,
      logLevel = 'error'})
      : _twilsockClient = twilsockClient ?? TwilsockClient(token, productId),
        _config = NotificationsConfiguration(null) {
    if (token == null || token.isEmpty) {
      throw Exception('Token is required for Notifications client');
    }

    // TwilsockClient twilsockCli ;
    // final trt = transport ?? twilsockCli;

    registrar = Registrar(productId, _twilsockClient, _twilsockClient, _config);

    _onTransportStateChange(_twilsockClient.isConnected);
    registrar.on('transportReady', (state) {
      _onRegistrationStateChange(state ? 'registered' : '');
    });
    registrar.on('stateChanged', (state) {
      _onRegistrationStateChange(state);
    });
    registrar.on('needReliableTransport', (b) {
      _onNeedReliableTransport(isNeeded: b is bool ? b : false);
    });
    _twilsockClient.on('message',
        (payload) => _routeMessage(payload['type'], payload['message']));
    _twilsockClient.on('connected', (notificationId) {
      _onTransportStateChange(true);
      registrar.setNotificationId(
          NotificationChannelType.twilsock, notificationId);
    });
    _twilsockClient.on('disconnected', (_) {
      _onTransportStateChange(false);
    });
    _config.updateToken = token;
    registrar.updateToken(token);
  }

  final TwilsockClient _twilsockClient;
  final NotificationsConfiguration _config;

  final int minTokenRefreshInterval;
  final String productId;
  Registrar registrar;
  final ReliableTransportState reliableTransportState =
      ReliableTransportState();

  TwilsockState get connectionState {
    if (_twilsockClient.state == TwilsockState.disconnected) {
      return TwilsockState.disconnected;
    } else if (_twilsockClient.state == TwilsockState.disconnecting) {
      return TwilsockState.disconnecting;
    } else if (_twilsockClient.state == TwilsockState.connected &&
        reliableTransportState.registration) {
      return TwilsockState.connected;
    } else if (_twilsockClient.state == TwilsockState.rejected) {
      return TwilsockState.denied;
    }
    return TwilsockState.connecting;
  }

  /// Routes messages to the external subscribers
  /// @private
  void _routeMessage(String type, dynamic message) {
    //_1.log.trace('Message arrived: ', type, message);
    emit('message',
        payload: PushNotification(payload: message, messageType: type));
  }

  void _onNeedReliableTransport({bool isNeeded = false}) {
    if (isNeeded) {
      _twilsockClient.connect();
    } else {
      _twilsockClient.disconnect();
    }
  }

  void _onRegistrationStateChange(String state) {
    reliableTransportState.registration = (state == 'registered');
    _updateTransportState();
  }

  void _onTransportStateChange(bool connected) {
    reliableTransportState.transport = connected;
    _updateTransportState();
  }

  void _updateTransportState() {
    final overallState =
        reliableTransportState.transport && reliableTransportState.registration;
    if (reliableTransportState.overall != overallState) {
      reliableTransportState.overall = overallState;
      //_1.log.info('Transport ready:', overallState);
      emit('transportReady', payload: overallState);
    }
    if (reliableTransportState.lastEmitted != connectionState) {
      reliableTransportState.lastEmitted = connectionState;
      emit('connectionStateChanged', payload: connectionState);
    }
  }

  /// Adds the subscription for the given message type
  /// @param {String} messageType The type of message that you want to receive
  /// @param {String} channelType. Supported are 'twilsock', 'gcm' and 'fcm'
  Future<void> subscribe(String messageType,
      {NotificationChannelType channelType =
          NotificationChannelType.twilsock}) async {
    //_1.log.trace('Add subscriptions for message type: ', messageType, channelType);
    return registrar.subscribe(messageType, channelType);
  }

  /// Remove the subscription for the particular message type
  /// @param {String} messageType The type of message that you don't want to receive anymore
  /// @param {String} channelType. Supported are 'twilsock', 'gcm' and 'fcm'
  Future<void> unsubscribe(String messageType,
      {NotificationChannelType channelType =
          NotificationChannelType.twilsock}) async {
    //_1.log.trace('Remove subscriptions for message type: ', messageType, channelType);
    return registrar.unsubscribe(messageType, channelType);
  }

  /// Handle incoming push notification.
  /// Client application should call this method when it receives push notifications and pass the received data
  /// @param {Object} message push message
  /// @return {PushNotification}
  PushNotification handlePushNotification(Map<String, dynamic> message) {
    return PushNotification(
        messageType: message['twi_message_type'], payload: message['payload']);
  }

  /// Set APN/GCM/FCM token to enable application register for a push messages
  /// @param {String} gcmToken/fcmToken Token received from GCM/FCM system
  void setPushRegistrationId(
      registrationId, NotificationChannelType channelType) {
    //_1.log.trace('Set push registration id', registrationId, channelType);
    registrar.setNotificationId(channelType, registrationId);
  }

  /// Updates auth token for registration
  /// @param {String} token Authentication token for registrations
  Future<void> updateToken(token) async {
    //_1.log.info('authTokenUpdated');
    if (_config.token == token) {
      return;
    }
    await _twilsockClient.updateToken(token);
    _config.updateToken = token;
    registrar.updateToken(token);
  }
}
//
// Fired when new message arrived.
// @param {Object} message'
// @event Client#message
//
//
// Fired when transport state has changed
// @param {boolean} transport state
// @event Client#transportReady
//
//
// Fired when transport state has been changed
// @param {String} transport state
// @event Client#connectionStateChanged
//
//
// These options can be passed to Client constructor
// @typedef {Object} Notifications#ClientOptions
// @property {String} [logLevel='error'] - The level of logging to enable. Valid options
//   (from strictest to broadest): ['silent', 'error', 'warn', 'info', 'debug', 'trace']
//
