import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/abstract_classes/transport.dart';
import 'package:twilio_conversations/src/enum/twilsock/event_sending_limitation.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/enum/twilsock/telemetry_point.dart';
import 'package:twilio_conversations/src/errors/twilsockerror.dart';
import 'package:twilio_conversations/src/vendor/deffered/deffered.dart';

import '../../config/twilsock.dart';
import 'cache/offline_storage.dart';
import 'cache/tocken_storage.dart';
import 'channel/twilsock.dart';
import 'channel/websocket_channel.dart';
import 'core/packet_interface.dart';
import 'core/registrations.dart';
import 'core/telemetry_tracker.dart';
import 'core/upstream.dart';
import 'models/telemetry_event_description.dart';
import 'util/telemetry_events.dart';

/// @alias Twilsock
/// @classdesc Client library for the Twilsock service
/// It allows to recevie service-generated updates as well as bi-directional transport
/// @fires Twilsock#message
/// @fires Twilsock#connected
/// @fires Twilsock#disconnected
/// @fires Twilsock#tokenAboutToExpire
/// @fires Twilsock#stateChanged
/// @fires Twilsock#connectionError
class TwilsockClient extends Stendo implements Transport {
  /// @param {String} token Twilio access token
  /// @param {String} productId Product identifier. Should be the same as a grant name in token
  TwilsockClient(String token, this.productId,
      {String continuationToken,
      PacketInterface transport,
      TwilsockChannel channel,
      TwilsockConfiguration config,
      Registrations registrations})
      : continuationToken =
            continuationToken ?? TokenStorage.getStoredToken(productId),
        _config = config ??
            TwilsockConfiguration(token, productId,
                continuationToken: continuationToken),
        _websocket = WebSocketChannel(config.url),
        _channel = channel,
        _transport = transport,
        _registrations = registrations ?? Registrations(transport),
// Send telemetry only when connected and initialised
        _telemetryTracker = TelemetryTracker(config, transport),
        super() {
    _channel ??= TwilsockChannel(_websocket, _transport, _config);
    _transport ??= PacketInterface(_websocket, _config);
    _upstream ??= Upstream(_transport, _channel, _config);
    //_1.log.setLevel(config.logLevel);

    _channel.on(
        'initialized', (_) => _telemetryTracker.canSendTelemetry = true);
    _websocket.on(
        'disconnected', (_) => _telemetryTracker.canSendTelemetry = false);
    registrations.on('registered', (id) => emit('registered', payload: id));
    _channel.on(
        'message',
        (payload) => Future.delayed(
            Duration.zero,
            () => emit('message', payload: {
                  'type': payload['type'],
                  'message': payload['message']
                })));
    _channel.on(
        'stateChanged',
        (state) => Future.delayed(
            Duration.zero, () => emit('stateChanged', payload: state)));
    _channel.on(
        'connectionError',
        (connectionError) => Future.delayed(Duration.zero,
            () => emit('connectionError', payload: connectionError)));
    _channel.on('tokenAboutToExpire',
        (_) => Future.delayed(Duration.zero, () => emit('tokenAboutToExpire')));
    _channel.on('tokenExpired',
        (_) => Future.delayed(Duration.zero, () => emit('tokenExpired')));
    _channel.on('connected', (_) => _registrations.updateRegistrations());
    _channel.on('connected', (_) => _upstream.sendPendingMessages());
    _channel.on('connected',
        (_) => Future.delayed(Duration.zero, () => emit('connected')));
    // Twilsock telemetry events
    _channel.on(
        'beforeConnect',
        (_) => _telemetryTracker.addPartialEvent(
            TelemetryEventDescription(
                title: 'Establish WebSocket connection',
                details: '',
                start: DateTime.now()),
            TelemetryEvents.TWILSOCK_CONNECT,
            TelemetryPoint.Start));
    _channel.on(
        'connected',
        (_) => _telemetryTracker.addPartialEvent(
            TelemetryEventDescription(
                title: 'Establish WebSocket connection',
                details: '',
                start: DateTime.now(),
                end: DateTime.now()),
            TelemetryEvents.TWILSOCK_CONNECT,
            TelemetryPoint.End));
    _channel.on(
        'beforeSendInit',
        (_) => _telemetryTracker.addPartialEvent(
            TelemetryEventDescription(
                title: 'Send Twilsock init',
                details: '',
                start: DateTime.now()),
            TelemetryEvents.TWILSOCK_INIT,
            TelemetryPoint.Start));
    _channel.on(
        'initialized',
        (_) => _telemetryTracker.addPartialEvent(
            TelemetryEventDescription(
                title: 'Send Twilsock init',
                details: 'Succeeded',
                start: DateTime.now(),
                end: DateTime.now()),
            TelemetryEvents.TWILSOCK_INIT,
            TelemetryPoint.End));
    _channel.on(
        'sendInitFailed',
        (_) => _telemetryTracker.addPartialEvent(
            TelemetryEventDescription(
                title: 'Send Twilsock init',
                details: 'Failed',
                start: DateTime.now(),
                end: DateTime.now()),
            TelemetryEvents.TWILSOCK_INIT,
            TelemetryPoint.End));
    _channel.on('initialized', (initReply) {
      handleStorageId(productId, initReply);
      TokenStorage.storeToken(initReply.continuationToken, productId);
      Future.delayed(
          Duration.zero, () => emit('initialized', payload: initReply));
    });
    _channel.on('disconnected',
        (_) => Future.delayed(Duration.zero, () => emit('disconnected')));
    _channel.on('disconnected', (_) => _upstream.rejectPendingMessages());
    _channel.on(
        'disconnected',
        (_) =>
            _offlineStorageDeferred.fail(TwilsockError('Client disconnected')));
    _offlineStorageDeferred.promise.onError((error, stackTrace) {});
  }

  final TwilsockConfiguration _config;
  TwilsockChannel _channel;
  final Registrations _registrations;
  Upstream _upstream;
  final TelemetryTracker _telemetryTracker;
  final Deferred _offlineStorageDeferred = Deferred();
  final WebSocketChannel _websocket;
  final String continuationToken;
  final String productId;
  PacketInterface _transport;

  void handleStorageId(productId, initReply) {
    if (!initReply.offlineStorage) {
      _offlineStorageDeferred.fail(TwilsockError('No offline storage id'));
    } else if (initReply.offlineStorage.hasOwnProperty(productId)) {
      try {
        _offlineStorageDeferred.set(
            OfflineProductStorage.create(initReply.offlineStorage[productId]));
        //_1.log.debug('Offline storage for '${productId}' product: ${JSON.Stringify(initReply.offlineStorage[productId])}.');
      } catch (e) {
        _offlineStorageDeferred.fail(TwilsockError(
            'Failed to parse offline storage for $productId ${json.encode(initReply.offlineStorage[productId])}. $e.'));
      }
    } else {
      _offlineStorageDeferred.fail(TwilsockError(
          'No offline storage id for $productId product: ${json.encode(initReply.offlineStorage)}'));
    }
  }

  /// Get offline storage ID
  /// @returns {Promise}
  Future get storageId {
    return _offlineStorageDeferred.promise;
  }

  /// Indicates if twilsock is connected now
  /// @returns {Boolean}
  @override
  bool get isConnected {
    return _channel.isConnected;
  }

  /// Current state
  /// @returns {String}
  @override
  TwilsockState get state {
    return _channel.state;
  }

  /// Update token
  /// @param {String} token
  /// @returns {Promise}
  Future updateToken(String token) {
    //_1.log.trace('updating token '${token}'');
    if (_config.token == token) {
      return null;
    }
    _config.updateToken(token);
    return _channel.updateToken(token);
  }

  /// Updates notification context.
  /// This method shouldn't be used anyone except twilio notifications library
  /// @param contextId id of notification context
  /// @param context value of notification context
  /// @private
  void setNotificationsContext(String contextId, Map<String, dynamic> context) {
    _registrations.setNotificationsContext(contextId, context);
  }

  /// Remove notification context.
  /// This method shouldn't be used anyone except twilio notifications library
  /// @param contextId id of notification context
  /// @private
  void removeNotificationsContext(String contextId) {
    _registrations.removeNotificationsContext(contextId);
  }

  /// Connect to the server
  /// @fires Twilsock#connected
  /// @public
  /// @returns {void}
  Future<void> connect() async {
    _channel.connect();
  }

  /// Disconnect from the server
  /// @fires Twilsock#disconnected
  /// @public
  /// @returns {Promise}
  Future<void> disconnect() async {
    _telemetryTracker
        .sendTelemetry(EventSendingLimitation.AnyEventsIncludingUnfinished);
    await _channel.disconnect();
  }

  /// Get HTTP request to upstream service
  /// @param {String} url Upstream service url
  /// @param {headers} headers Set of custom headers
  /// @param {String} [grant] The product grant
  /// @returns {Promise}
  Future get(String url, Map<String, dynamic> headers, String grant) async {
    _telemetryTracker.sendTelemetry(EventSendingLimitation
        .AnyEvents); // send collected telemetry (if any) before upstream message shipment
    return await _upstream.send('GET', url, headers, null, grant);
  }

  /// Post HTTP request to upstream service
  /// @param {String} url Upstream service url
  /// @param {headers} headers Set of custom headers
  /// @param {body} body Body to send
  /// @param {String} [grant] The product grant
  /// @returns {Promise}
  Future post(String url, Map<String, dynamic> headers, dynamic body,
      String grant) async {
    _telemetryTracker.sendTelemetry(EventSendingLimitation
        .AnyEvents); // send collected telemetry (if any) before upstream message shipment
    return await _upstream.send('POST', url, headers, body, grant);
  }

  /// Put HTTP request to upstream service
  /// @param {String} url Upstream service url
  /// @param {headers} headers Set of custom headers
  /// @param {body} body Body to send
  /// @param {String} [grant] The product grant
  /// @returns {Promise}
  Future put(String url, Map<String, dynamic> headers,
      Map<String, dynamic> body, String grant) {
    _telemetryTracker.sendTelemetry(EventSendingLimitation
        .AnyEvents); // send collected telemetry (if any) before upstream message shipment
    return _upstream.send('PUT', url, headers, body, grant);
  }

  /// Delete HTTP request to upstream service
  /// @param {String} url Upstream service url
  /// @param {headers} headers Set of custom headers
  /// @param {String} [grant] The product grant
  /// @returns {Promise}
  Future delete(String url, Map<String, dynamic> headers, String grant) {
    _telemetryTracker.sendTelemetry(EventSendingLimitation
        .AnyEvents); // send collected telemetry (if any) before upstream message shipment
    return _upstream.send('DELETE', url, headers, null, grant);
  }

  /// Submits internal telemetry event. Not to be used for any customer and/or sensitive data.
  /// @param {TelemetryEventDescription} event Event details.
  /// @returns {void}
  void addTelemetryEvent(TelemetryEventDescription event) {
    _telemetryTracker.addTelemetryEvent(event);
    _telemetryTracker
        .sendTelemetryIfMinimalPortionCollected(); // send telemetry if need
  }

  /// Submits internal telemetry event. Not to be used for any customer and/or sensitive data.
  /// @param {TelemetryEventDescription} event Event details.
  /// @param {String} eventKey Unique event key.
  /// @param {TelemetryPoint} point Is this partial event for start or end of measurement.
  /// @returns {void}
  void addPartialTelemetryEvent(
      TelemetryEventDescription event, String eventKey, TelemetryPoint point) {
    _telemetryTracker.addPartialEvent(event, eventKey, point);
    if (point == TelemetryPoint.End) {
      // this telemetry event is complete, so minimal portion could become ready to send
      _telemetryTracker
          .sendTelemetryIfMinimalPortionCollected(); // send telemetry if need
    }
  }
}

//
// Twilsock destination address descriptor
// @typedef {Object} Twilsock#Address
// @property {String} method - HTTP method. (POST, PUT, etc)
// @property {String} host - host name without path. (e.g. my.company.com)
// @property {String} path - path on the host (e.g. /my/app/to/call.php)
//
//
// Twilsock upstream message
// @typedef {Object} Twilsock#Message
// @property {Twilsock#Address} to - destination address
// @property {Object} headers - HTTP headers
// @property {Object} body - Body
//
//
// Fired when new message received
// @param {Twilsock#Message} message
// @event Twilsock#message
//
//
// Fired when socket connected
// @param {String} URI of endpoint
// @event Twilsock#connected
//
//
// Fired when socket disconnected
// @event Twilsock#disconnected
//
//
// Fired when token is about to expire and should be updated
// @event Twilsock#tokenAboutToExpire
//
//
// Fired when socket connected
// @param {('connecting'|'connected'|'rejected'|'disconnecting'|'disconnected')} state - general twilsock state
// @event Twilsock#stateChanged
//
//
// Fired when connection is interrupted by unexpected reason
// @type {Object}
// @property {Boolean} terminal - twilsock will stop connection attempts
// @property {String} message - root cause
// @property {Number} [httpStatusCode] - http status code if available
// @property {Number} [errorCode] - Twilio public error code if available
// @event Twilsock#connectionError
//
