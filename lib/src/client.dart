import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/core/network.dart';
import 'package:twilio_conversations/src/core/session/models/command.dart';
import 'package:twilio_conversations/src/enum/conversations/push_notification_type.dart';
import 'package:twilio_conversations/src/enum/sync/connection_state.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/enum/twilsock/telemetry_point.dart';
import 'package:twilio_conversations/src/models/push_notification.dart';
import 'package:twilio_conversations/src/services/notifications/client.dart';
import 'package:twilio_conversations/src/services/router/client.dart';
import 'package:twilio_conversations/src/services/router/network/transport.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_list/sync_list.dart';
import 'package:twilio_conversations/src/services/websocket/client.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';

import 'config/client_info.dart';
import 'config/conversations.dart';
import 'const/notificationtypes.dart';
import 'contexts/conversations.dart';
import 'contexts/users.dart';
import 'core/readhorizon.dart';
import 'core/session/session.dart';
import 'core/typingindicator.dart';
import 'enum/notification/channel_type.dart';
import 'models/conversation.dart';
import 'models/user.dart';
import 'services/websocket/models/telemetry_event_description.dart';
import 'utils/sync_paginator.dart';

/// A Client is a starting point to access Twilio Conversations functionality.
///
/// @property {Client#ConnectionState} connectionState - Client connection state
/// @property [bool] reachabilityEnabled - Client reachability state
/// @property {User} user - Information for logged in user
/// @property [String] version - Current version of Conversations client
///
/// @fires Client#connectionError
/// @fires Client#connectionStateChanged
/// @fires Client#conversationAdded
/// @fires Client#conversationJoined
/// @fires Client#conversationLeft
/// @fires Client#conversationRemoved
/// @fires Client#conversationUpdated
/// @fires Client#participantJoined
/// @fires Client#participantLeft
/// @fires Client#participantUpdated
/// @fires Client#messageAdded
/// @fires Client#messageRemoved
/// @fires Client#messageUpdated
/// @fires Client#pushNotification
/// @fires Client#tokenAboutToExpire
/// @fires Client#tokenExpired
/// @fires Client#typingEnded
/// @fires Client#typingStarted
/// @fires Client#userSubscribed
/// @fires Client#userUnsubscribed
/// @fires Client#userUpdated
class ConversationClientOptions {
  String region;
  String productId;
  TwilsockClient twilsockClient;
  TwilsockClient transport;
  NotificationsClient notificationsClient;
  SyncClient syncClient;
  int typingIndicatorTimeoutOverride;
  int consumptionReportIntervalOverride;
  String httpCacheIntervalOverride;
  int userInfosToSubscribeOverride;
  bool retryWhenThrottledOverride;
  BackoffRetrierConfig backoffConfigOverride;
  var Chat;
  var Sync;
  var Notification;
  var Twilsock;
  ClientInfo clientMetadata;
}

class ConversationClientServices {
  TwilsockClient twilsockClient;
  SyncClient<Command> syncClient;
  Session session;
  TwilsockClient transport;
  ConversationNetwork network;
  Users users;
  TypingIndicator typingIndicator;
  NotificationsClient notificationClient;
  ReadHorizon readHorizon;
  SyncList syncList;
  McsClient mcsClient;
}

///
class Client extends Stendo {
  /**
   * These options can be passed to Client constructor.
   * @typedef {Object} Client#ClientOptions
   * @property [String] [logLevel='error'] - The level of logging to enable. Valid options
   *   (from strictest to broadest): ['silent', 'error', 'warn', 'info', 'debug', 'trace']
   */
  /**
   * These options can be passed to {@link Client#createConversation}.
   * @typedef {Object} Client#CreateConversationOptions
   * @property {any} [attributes] - Any custom attributes to attach to the Conversation
   * @property [String] [friendlyName] - The non-unique display name of the Conversation
   * @property [String] [uniqueName] - The unique identifier of the Conversation
   */
  /**
   * Connection state of Client.
   * @typedef {('connecting'|'connected'|'disconnecting'|'disconnected'|'denied')} Client#ConnectionState
   */
  /// Notifications channel type.
  /// @typedef {('fcm'|'apn')} Client#NotificationsChannelType
  Client(String token, ConversationClientOptions options)
      : region = options.region,
        super() {
    connectionState = TwilsockState.connecting;

    final info = ClientInfo();

    // setLevel(options.logLevel);
    final productId = options.productId ?? 'ip_messaging';
    // Filling ClientMetadata
    options.clientMetadata = info;

    // Enable session local storage for Sync
    options.Sync = options.Sync;
    options.Sync.enableSessionStorage ??= true;
    if (options.region != null) {
      options.Sync.region = options.region;
    }
    if (token == null) {
      throw Exception('A valid Twilio token should be provided');
    }

    config = ConversationsConfiguration(
        region: region,
        typingIndicatorTimeoutOverride: options.typingIndicatorTimeoutOverride,
        httpCacheIntervalOverride: options.httpCacheIntervalOverride,
        consumptionReportIntervalOverride:
            options.consumptionReportIntervalOverride,
        userInfosToSubscribeOverride: options.userInfosToSubscribeOverride,
        retryWhenThrottledOverride: options.retryWhenThrottledOverride,
        backoffConfigOverride: options.backoffConfigOverride,
        productId: productId);
    options.twilsockClient =
        options.twilsockClient ?? TwilsockClient(token, productId);
    options.transport = options.transport ?? options.twilsockClient;
    options.notificationsClient = options.notificationsClient ??
        NotificationsClient(token,
            transport: services.transport,
            twilsockClient: services.twilsockClient,
            productId: options.productId);
    options.syncClient = options.syncClient ??
        SyncClient(
          token,
          twilsock: services.twilsockClient,
          notifications: services.notificationClient,
          network: services.network,
        );
    services.syncClient = options.syncClient;
    services.transport = options.transport;
    services.twilsockClient = options.twilsockClient;
    services.notificationClient = options.notificationsClient;
    services.session = Session(services.syncClient, config);
    sessionPromise = services.session.initialize();
    services.network = ConversationNetwork(config,
        session: services.session, transport: services.transport);
    services.users = Users(
        session: services.session,
        network: services.network,
        syncClient: services.syncClient);
    services.users.on('userSubscribed', (_) => emit('userSubscribed'));
    services.users
        .on('userUpdated', (args) => emit('userUpdated', payload: args));
    services.users.on('userUnsubscribed', (_) => emit('userUnsubscribed'));
    services.twilsockClient.on('tokenAboutToExpire',
        (ttl) => emit('tokenAboutToExpire', payload: ttl));
    services.twilsockClient.on('tokenExpired', (_) => emit('tokenExpired'));
    services.twilsockClient.on(
        'connectionError', (error) => emit('connectionError', payload: error));
    services.readHorizon = ReadHorizon(services.session);
    services.typingIndicator = TypingIndicator(config, getConversationBySid,
        transport: services.twilsockClient,
        notificationClient: services.notificationClient //todo

        );
    conversations = Conversations(
        session: services.session,
        syncClient: services.syncClient,
        syncList: services.syncList,
        users: services.users,
        typingIndicator: services.typingIndicator,
        readHorizon: services.readHorizon,
        network: services.network,
        mcsClient: services.mcsClient);
    conversationsPromise = sessionPromise.then((_) {
      conversations.on('conversationAdded', (_) => emit('conversationAdded'));
      conversations.on(
          'conversationRemoved', (_) => emit('conversationRemoved'));
      conversations.on('conversationJoined', (_) => emit('conversationJoined'));
      conversations.on('conversationLeft', (_) => emit('conversationLeft'));
      conversations.on('conversationUpdated',
          (args) => emit('conversationUpdated', payload: args));
      conversations.on('participantJoined', (_) => emit('participantJoined'));
      conversations.on('participantLeft', (_) => emit('participantLeft'));
      conversations.on('participantUpdated',
          (args) => emit('participantUpdated', payload: args));
      conversations.on('messageAdded', (_) => emit('messageAdded'));
      conversations.on(
          'messageUpdated', (args) => emit('messageUpdated', payload: args));
      conversations.on('messageRemoved', (_) => emit('messageRemoved'));
      conversations.on('typingStarted', (_) => emit('typingStarted'));
      conversations.on('typingEnded', (_) => emit('typingEnded'));
      return conversations.fetchConversations();
    }).then((_) => conversations);
    services.notificationClient.on('connectionStateChanged', (state) {
      var changedConnectionState;
      switch (state) {
        case SyncConnectionState.connected:
          changedConnectionState = SyncConnectionState.connected;
          break;
        case SyncConnectionState.denied:
          changedConnectionState = SyncConnectionState.denied;
          break;
        case SyncConnectionState.disconnecting:
          changedConnectionState = SyncConnectionState.disconnecting;
          break;
        case SyncConnectionState.disconnected:
          changedConnectionState = SyncConnectionState.disconnected;
          break;
        default:
          changedConnectionState = SyncConnectionState.connecting;
      }
      if (changedConnectionState != connectionState) {
        connectionState = changedConnectionState;
        emit('connectionStateChanged', payload: connectionState);
      }
    });
    fpaToken = token;
  }

  final String region;
  TwilsockState connectionState;
  ConversationsConfiguration config;
  Future<Conversations> conversationsPromise;
  String fpaToken;
  Conversations conversations;
  Future sessionPromise;
  ConversationClientServices services;

  /// Factory method to create Conversations client instance.
  ///
  /// @param [String] token - Access token
  /// @param {Client#ClientOptions} [options] - Options to customize the Client
  /// @returns {Future<Client>}
  static Future create(String token, ConversationClientOptions options) async {
    final client = Client(token, options);
    final startupEvent = 'conversations.client.startup';
    client.services.twilsockClient.addPartialTelemetryEvent(
        TelemetryEventDescription(
            title: startupEvent,
            details: 'Conversations client startup',
            start: DateTime.now()),
        startupEvent,
        TelemetryPoint.Start);
    await client.initialize();
    client.services.twilsockClient.addPartialTelemetryEvent(
        TelemetryEventDescription(
            title: '', details: '', start: DateTime.now()),
        startupEvent,
        TelemetryPoint.End);
    return client;
  }

  User get user => services.users.myself;
  bool get reachabilityEnabled => services.session.reachabilityEnabled;
  String get token => fpaToken;
  Future<List> subscribeToPushNotifications(channelType) {
    final subscriptions = [];
    [
      NotificationTypes.NEW_MESSAGE,
      NotificationTypes.ADDED_TO_CONVERSATION,
      NotificationTypes.REMOVED_FROM_CONVERSATION,
      NotificationTypes.TYPING_INDICATOR,
      NotificationTypes.CONSUMPTION_UPDATE
    ].forEach((messageType) {
      subscriptions.add(services.notificationClient
          .subscribe(messageType, channelType: channelType));
    });
    return Future.value(subscriptions);
  }

  Future<List> unsubscribeFromPushNotifications(channelType) {
    final subscriptions = [];
    [
      NotificationTypes.NEW_MESSAGE,
      NotificationTypes.ADDED_TO_CONVERSATION,
      NotificationTypes.REMOVED_FROM_CONVERSATION,
      NotificationTypes.TYPING_INDICATOR,
      NotificationTypes.CONSUMPTION_UPDATE
    ].forEach((messageType) {
      subscriptions.add(services.notificationClient
          .unsubscribe(messageType, channelType: channelType));
    });
    return Future.value(subscriptions);
  }

  Future initialize() async {
    await sessionPromise;
    Client.supportedPushChannels
        .forEach((channelType) => subscribeToPushNotifications(channelType));
    final links = await services.session.getSessionLinks();
    services.transport = null;
    services.mcsClient = McsClient(fpaToken, links.mediaServiceUrl,
        region: region, transport: McsTransport());
    services.typingIndicator.initialize();
  }

  /// Gracefully shutting down library instance.
  /// @public
  /// @returns {Future<void>}
  @override
  Future<void> shutdown() async {
    await services.twilsockClient.disconnect();
    super.shutdown();
  }

  /// Update the token used by the Client and re-register with Conversations services.
  /// @param [String] token - Access token
  /// @public
  /// @returns {Future<Client>}
  Future<Client> updateToken(String token) async {
    // info('updateToken');
    if (fpaToken == token) {
      return this;
    }
    await services.twilsockClient
        .updateToken(token)
        .then((_) => fpaToken = token)
        .then((_) => services.mcsClient.updateToken(token))
        .then((_) => sessionPromise);
    return this;
  }

  /// Get a known Conversation by its SID.
  /// @param [String] conversationSid - Conversation sid
  /// @returns {Future<Conversation>}
  Future<Conversation> getConversationBySid(String conversationSid) async {
    await conversations.syncListRead.promise;
    Conversation conversation =
        await conversations.getConversation(conversationSid);
    if (conversation != null) {
      conversation =
          await conversations.getWhisperConversation(conversationSid);
    }
    if (conversation == null) {
      throw Exception('Conversation with SID $conversationSid is not found.');
    }
    return conversation;
  }

  /// Get a known Conversation by its unique identifier name.
  /// @param [String] uniqueName - The unique identifier name of the Conversation to get
  /// @returns {Future<Conversation>}
  Future<Conversation> getConversationByUniqueName(String uniqueName) async {
    await conversations.syncListRead.promise;
    final conversation =
        await conversations.getConversationByUniqueName(uniqueName);
    if (conversation == null) {
      throw Exception(
          'Conversation with unique name $uniqueName is not found.');
    }
    return conversation;
  }

  /// Get the current list of all subscribed Conversations.
  /// @returns {Future<Paginator<Conversation>>}
  Future<SyncPaginator<Conversation>> getSubscribedConversations(
      {String key, String from, int pageSize, String order}) {
    return conversationsPromise.then((conversations) =>
        conversations.getConversations(
            key: key, from: from, pageSize: pageSize, order: order));
  }

  /// Create a Conversation on the server and subscribe to its events.
  /// The default is a Conversation with an empty friendlyName.
  /// @param {Client#CreateConversationOptions} [options] - Options for the Conversation
  /// @returns {Future<Conversation>}
  Future<Conversation> createConversation(
      {Map<String, dynamic> attributes,
      String uniqueName,
      friendlyName}) async {
    return conversationsPromise.then((conversationsEntity) =>
        conversationsEntity.addConversation(
            attributes: attributes,
            uniqueName: uniqueName,
            friendlyName: friendlyName));
  }

  /// Registers for push notifications.
  /// @param {Client#NotificationsChannelType} channelType - 'apn' and 'fcm' are supported
  /// @param [String] registrationId - Push notification id provided by the platform
  /// @returns {Future<void>}
  Future setPushRegistrationId(
      NotificationChannelType channelType, String registrationId) async {
    await subscribeToPushNotifications(channelType).then((_) {
      return services.notificationClient
          .setPushRegistrationId(registrationId, channelType);
    });
  }

  /// Unregisters from push notifications.
  /// @param {Client#NotificationsChannelType} channelType - 'apn' and 'fcm' are supported
  /// @returns {Future<void>}
  Future<void> unsetPushRegistrationId(
      NotificationChannelType channelType) async {
    if (!Client.supportedPushChannels.contains(channelType)) {
      throw Exception(
          'Invalid or unsupported channelType: ' + channelType.toString());
    }
    await unsubscribeFromPushNotifications(channelType);
  }

  static List<NotificationChannelType> get supportedPushChannels =>
      [NotificationChannelType.fcm, NotificationChannelType.apn];
  static Map<String, String> get supportedPushDataFields => {
        'conversation_sid': 'conversationSid',
        'message_sid': 'messageSid',
        'message_index': 'messageIndex'
      };

  static Map parsePushNotificationChatData(Map<String, dynamic> data) {
    final result = {};
    for (final key in Client.supportedPushDataFields.keys) {
      if (data[key] != null) {
        if (key == 'message_index') {
          if (int.tryParse(data[key]) != null) {
            result[Client.supportedPushDataFields[key]] =
                int.tryParse((data[key]));
          }
        } else {
          result[Client.supportedPushDataFields[key]] = data[key];
        }
      }
    }
    return result;
  }

  /// Static method for push notification payload parsing. Returns parsed push as {@link PushNotification} object
  /// @param {Object} notificationPayload - Push notification payload
  /// @returns {PushNotification|Error}
  static PushNotification parsePushNotification(
      Map<String, dynamic> notificationPayload) {
    // debug('parsePushNotification, notificationPayload=', notificationPayload);
    // APNS specifics
    if (notificationPayload['aps'] != null) {
      if (notificationPayload['twi_message_type'] == null) {
        throw Exception(
            'Provided push notification payload does not contain Programmable Chat push notification type');
      }
      final data = Client.parsePushNotificationChatData(notificationPayload);
      final apsPayload = notificationPayload['aps'];
      var body;
      var title;
      if (apsPayload['alert'] is String) {
        body = apsPayload['alert'];
      } else {
        body = apsPayload['alert']['body'];
        title = apsPayload['alert']['title'];
      }
      return PushNotification(
          title: title,
          body: body,
          sound: apsPayload.sound,
          badge: apsPayload.badge,
          action: apsPayload.category,
          type: notificationTypeFromString(
              notificationPayload['twi_message_type']),
          data: data);
    }
    // FCM specifics
    if (notificationPayload['data'] != null) {
      final dataPayload = notificationPayload['data'];
      if (dataPayload['twi_message_type'] == null) {
        throw Exception(
            'Provided push notification payload does not contain Programmable Chat push notification type');
      }
      final data =
          Client.parsePushNotificationChatData(notificationPayload['data']);
      return PushNotification(
          title: dataPayload['twi_title'],
          body: dataPayload['twi_body'],
          sound: dataPayload['twi_sound'],
          action: dataPayload['twi_action'],
          type: dataPayload['twi_message_type'],
          data: data);
    }
    throw Exception(
        'Provided push notification payload is not Programmable Chat notification');
  }

  /// Handle push notification payload parsing and emits event {@link Client#event:pushNotification} on this {@link Client} instance.
  /// @param {Object} notificationPayload - Push notification payload
  /// @returns {Future<void>}
  Future<void> handlePushNotification(
      Map<String, dynamic> notificationPayload) async {
    // debug('handlePushNotification, notificationPayload=', notificationPayload);
    emit('pushNotification',
        payload: parsePushNotification(notificationPayload));
  }

  /// Gets user for given identity, if it's in subscribed list - then return the user object from it,
  /// if not - then subscribes and adds user to the subscribed list.
  /// @param [String] identity - Identity of User
  /// @returns {Future<User>} Fully initialized user
  Future<User> getUser(String identity) {
    return services.users.getUser(identity);
  }

  /// @returns {Future<List<User>>} List of subscribed User objects
  Future getSubscribedUsers() {
    return services.users.getSubscribedUsers();
  }
}
// Client.version = SDK_VERSION;
// Client.supportedPushChannels = ['fcm', 'apn'];
// Client.supportedPushDataFields = {
// 'conversation_sid': 'conversationSid',
// 'message_sid': 'messageSid',
// 'message_index': 'messageIndex'
// };

///
/// Fired when a Conversation becomes visible to the Client. The event is also triggered when the client creates a new Conversation.
/// Fired for all conversations Client has joined.
/// @event Client#conversationAdded
/// @type {Conversation}
///
///
/// Fired when the Client joins a Conversation.
/// @event Client#conversationJoined
/// @type {Conversation}
///
///
/// Fired when the Client leaves a Conversation.
/// @event Client#conversationLeft
/// @type {Conversation}
///
///
/// Fired when a Conversation is no longer visible to the Client.
/// @event Client#conversationRemoved
/// @type {Conversation}
///
///
/// Fired when a Conversation's attributes or metadata have been updated.
/// During Conversation's {@link Client.create| creation and initialization} this event might be fired multiple times
/// for same joined or created Conversation as new data is arriving from different sources.
/// @event Client#conversationUpdated
/// @type {Object}
/// @property {Conversation} conversation - Updated Conversation
/// @property {Conversation#UpdateReason[]} updateReasons - List of Conversation's updated event reasons
///
///
/// Fired when Client's connection state has been changed.
/// @event Client#connectionStateChanged
/// @type {Client#ConnectionState}
///
///
/// Fired when a Participant has joined the Conversation.
/// @event Client#participantJoined
/// @type {Participant}
///
///
/// Fired when a Participant has left the Conversation.
/// @event Client#participantLeft
/// @type {Participant}
///
///
/// Fired when a Participant's fields has been updated.
/// @event Client#participantUpdated
/// @type {Object}
/// @property {Participant} participant - Updated Participant
/// @property {Participant#UpdateReason[]} updateReasons - List of Participant's updated event reasons
///
///
/// Fired when a new Message has been added to the Conversation on the server.
/// @event Client#messageAdded
/// @type {Message}
///
///
/// Fired when Message is removed from Conversation's message list.
/// @event Client#messageRemoved
/// @type {Message}
///
///
/// Fired when an existing Message's fields are updated with new values.
/// @event Client#messageUpdated
/// @type {Object}
/// @property {Message} message - Updated Message
/// @property {Message#UpdateReason[]} updateReasons - List of Message's updated event reasons
///
///
/// Fired when token is about to expire and needs to be updated.
/// @event Client#tokenAboutToExpire
/// @type {void}
///
///
/// Fired when token is expired.
/// @event Client#tokenExpired
/// @type {void}
///
///
/// Fired when a Participant has stopped typing.
/// @event Client#typingEnded
/// @type {Participant}
///
///
/// Fired when a Participant has started typing.
/// @event Client#typingStarted
/// @type {Participant}
///
///
/// Fired when client received (and parsed) push notification via one of push channels (apn or fcm).
/// @event Client#pushNotification
/// @type {PushNotification}
///
///
/// Fired when the Client is subscribed to a User.
/// @event Client#userSubscribed
/// @type {User}
///
///
/// Fired when the Client is unsubscribed from a User.
/// @event Client#userUnsubscribed
/// @type {User}
///
///
/// Fired when the User's properties or reachability status have been updated.
/// @event Client#userUpdated
/// @type {Object}
/// @property {User} user - Updated User
/// @property {User#UpdateReason[]} updateReasons - List of User's updated event reasons
///
///
/// Fired when connection is interrupted by unexpected reason
/// @event Client#connectionError
/// @type {Object}
/// @property [bool] terminal - twilsock will stop connection attempts
/// @property [String] message - root cause
/// @property [int] [httpStatusCode] - http status code if available
/// @property [int] [errorCode] - Twilio public error code if available
///
