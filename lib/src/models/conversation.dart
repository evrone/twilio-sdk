import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/enum/conversations/lifecycle_state.dart';
import 'package:twilio_conversations/src/enum/conversations/notification_level.dart';
import 'package:twilio_conversations/src/enum/conversations/status.dart';
import 'package:twilio_conversations/src/enum/sync/open_mode.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/models/message.dart';
import 'package:twilio_conversations/src/services/router/client.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_document/sync_document.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

import '../contexts/conversations.dart';
import '../contexts/messages.dart';
import '../contexts/participants.dart';
import '../contexts/users.dart';
import '../core/network.dart';
import '../core/readhorizon.dart';
import '../core/session/session.dart';
import '../core/typingindicator.dart';
import 'participant.dart';

class FieldMappings {
  const FieldMappings();
  static const String lastMessage = 'lastMessage';
  static const String attributes = 'attributes';
  static const String createdBy = 'createdBy';
  static const String dateCreated = 'dateCreated';
  static const String dateUpdated = 'dateUpdated';
  static const String friendlyName = 'friendlyName';
  static const String lastConsumedMessageIndex = 'lastConsumedMessageIndex';
  static const String notificationLevel = 'notificationLevel';
  static const String sid = 'sid';
  static const String status = 'status';
  static const String uniqueName = 'uniqueName';
  static const String state = 'state';

  String operator [](String key) {
    return _map[key];
  }

  static const _map = {
    'lastMessage': 'lastMessage',
    'attributes': 'attributes',
    'createdBy': 'createdBy',
    'dateCreated': 'dateCreated',
    'dateUpdated': 'dateUpdated',
    'friendlyName': 'friendlyName',
    'lastConsumedMessageIndex': 'lastConsumedMessageIndex',
    'notificationLevel': 'notificationLevel',
    'sid': 'sid',
    'status': 'status',
    'uniqueName': 'uniqueName',
    'state': 'state'
  };
}

const fieldMappings = FieldMappings();

ConversationUpdateReason localKeyToUpdateReason(String key) {
  switch (key) {
    case FieldMappings.attributes:
      return ConversationUpdateReason.attributes;
    case FieldMappings.status:
      return ConversationUpdateReason.status;
    case FieldMappings.lastMessage:
      return ConversationUpdateReason.lastMessage;
    case FieldMappings.notificationLevel:
      return ConversationUpdateReason.notificationLevel;
    case FieldMappings.friendlyName:
      return ConversationUpdateReason.friendlyName;
    case FieldMappings.dateCreated:
      return ConversationUpdateReason.dateCreated;
    case FieldMappings.dateUpdated:
      return ConversationUpdateReason.dateUpdated;
    case FieldMappings.lastConsumedMessageIndex:
      return ConversationUpdateReason.lastReadMessageIndex;
    case FieldMappings.createdBy:
      return ConversationUpdateReason.createdBy;
    case FieldMappings.state:
      return ConversationUpdateReason.state;
    case 'lastReadMessageIndex':
      return ConversationUpdateReason.lastReadMessageIndex;
  }
  return null;
}

DateTime parseTime(String timeString) {
  try {
    return DateTime.tryParse(timeString);
  } catch (e) {
    return null;
  }
}

enum ConversationUpdateReason {
  attributes,
  createdBy,
  dateCreated,
  dateUpdated,
  friendlyName,
  lastReadMessageIndex,
  state,
  status,
  uniqueName,
  lastMessage,
  notificationLevel
}

class ConversationServices {
  ConversationServices(
      {this.session,
      this.users,
      this.syncClient,
      this.network,
      this.mcsClient,
      this.typingIndicator,
      this.readHorizon});
  Session session;
  Users users;
  TypingIndicator typingIndicator;
  ReadHorizon readHorizon;
  ConversationNetwork network;
  McsClient mcsClient;
  SyncClient syncClient;
}

class ConversationDescriptor {
  ConversationDescriptor(
      {this.dateCreated,
      this.attributes,
      this.dateUpdated,
      this.friendlyName,
      this.entityName,
      this.lastConsumedMessageIndex,
      this.notificationLevel,
      this.channel,
      this.status,
      this.uniqueName,
      this.createdBy});
  String channel;
  String entityName;
  String uniqueName;
  ConversationStatus status;
  Map<String, dynamic> attributes;
  String createdBy;
  String friendlyName;
  int lastConsumedMessageIndex;
  String dateCreated;
  String dateUpdated;
  ConversationNotificationLevel notificationLevel;

  ConversationDescriptor.fromMap(Map<String, dynamic> map)
      : lastConsumedMessageIndex = map['lastConsumedMessageIndex'],
        status = conversationStatusFromString(map['status']),
        friendlyName = map['friendly_name'],
        dateUpdated = map['date_updated'],
        dateCreated = map['date_created'],
        uniqueName = map['unique_name'],
        entityName = map['entity_name'],
        createdBy = map['created_by'],
        attributes = map['attributes'],
        channel = map['channel'],
        notificationLevel = map['notificationLevel'];
  Map<String, dynamic> toMap() => {
        'channel': channel,
        'entityName': entityName,
        'uniqueName': uniqueName,
        'status': status,
        'attributes': attributes,
        'createdBy': createdBy,
        'friendlyName': friendlyName,
        'lastConsumedMessageIndex': lastConsumedMessageIndex,
        'dateCreated': dateCreated,
        'dateUpdated': dateUpdated,
        'notificationLevel': notificationLevel,
      };

  bool get isEmpty =>
      channel == null &&
          entityName == null &&
          uniqueName == null &&
          status == null ||
      attributes == null &&
          createdBy == null &&
          friendlyName == null &&
          lastConsumedMessageIndex == null &&
          dateCreated == null &&
          dateUpdated == null &&
          notificationLevel == null;

  bool get isNotEmpty => !isEmpty;
}

class ConversationChannelState {
  ConversationChannelState(
      {this.createdBy,
      this.uniqueName,
      this.notificationLevel,
      this.friendlyName,
      this.dateUpdated,
      this.attributes,
      this.dateCreated,
      this.lastReadMessageIndex,
      this.status = ConversationStatus.notParticipating});
  String uniqueName;
  ConversationStatus status;
  Map<String, dynamic> attributes;
  String createdBy;
  DateTime dateCreated;
  DateTime dateUpdated;
  String friendlyName;
  int lastReadMessageIndex;
  ConversationNotificationLevel notificationLevel;
  LastMessage lastMessage;
  ConversationLifecycleState state = ConversationLifecycleState.active;
}
//
// class UpdatedEventArgs {
//   Conversation conversation;
//   List<ConversationUpdateReason> updateReasons;
// }

// abstract class SendMediaOptions {
//   contentType: String;
//   media;
// }
// abstract class SendEmailOptions {
//   subject?: String;
// }
class LastMessage {
  LastMessage({this.index, this.dateCreated});
  int index;
  DateTime dateCreated;
}

/// @classdesc A Conversation represents communication between multiple Conversations Clients
/// @property {any} attributes - The Conversation's custom attributes
/// @property [String] createdBy - The identity of the User that created this Conversation
/// @property [DateTime] dateCreated - The DateTime this Conversation was created
/// @property [DateTime] dateUpdated - The DateTime this Conversation was last updated
/// @property [String] [friendlyName] - The Conversation's name
/// @property {Number|null} lastReadMessageIndex - Index of the last Message the User has read in this Conversation
/// @property {Conversation#LastMessage} lastMessage - Last Message sent to this Conversation
/// @property {Conversation#NotificationLevel} notificationLevel - User Notification level for this Conversation
/// @property [String] sid - The Conversation's unique system identifier
/// @property {Conversation#Status} status - The Conversation's status
/// @property {Conversation#State} state - The Conversation's state
/// @property [String] uniqueName - The Conversation's unique name
/// @fires Conversation#participantJoined
/// @fires Conversation#participantLeft
/// @fires Conversation#participantUpdated
/// @fires Conversation#messageAdded
/// @fires Conversation#messageRemoved
/// @fires Conversation#messageUpdated
/// @fires Conversation#typingEnded
/// @fires Conversation#typingStarted
/// @fires Conversation#updated
/// @fires Conversation#removed
class Conversation extends Stendo {
  ///
  /// These options can be passed to {@link Conversation#sendMessage}.
  /// @typedef {Object} Conversation#SendMediaOptions
  /// @property [String] contentType - content type of media
  /// @property {String | Buffer} media - content to post
  ///
  ///
  /// These options can be passed to {@link Conversation#sendMessage}.
  /// @typedef {Object} Conversation#SendEmailOptions
  /// @property [String] subject - subject for the message. Ignored for media messages.
  ///
  ///
  /// The update reason for <code>updated</code> event emitted on Conversation
  /// @typedef {('attributes' | 'createdBy' | 'dateCreated' | 'dateUpdated' |
  ///  'friendlyName' | 'lastReadMessageIndex' | 'state' | 'status' | 'uniqueName' | 'lastMessage' |
  ///  'notificationLevel' )} Conversation#UpdateReason
  ///
  ///
  /// The status of the Conversation, relative to the Client: whether the Conversation has been <code>joined</code> or the Client is
  /// <code>notParticipating</code> in the Conversation.
  /// @typedef {('notParticipating' | 'joined')} Conversation#Status
  ///
  ///
  /// The User's Notification level for Conversation, determines whether the currently logged-in User will receive
  /// pushes for events in this Conversation. Can be either <code>muted</code> or <code>default</code>,
  /// where <code>default</code> defers to global Service push configuration.
  /// @typedef {('default' | 'muted')} Conversation#NotificationLevel
  ///
  /// The Conversation's state.
  /// @typedef {Object} Conversation#State
  /// @property {('active' | 'inactive' | 'closed')} current - the current state
  /// @property [DateTime] dateUpdated - date at which the latest conversation state update happened
  Conversation(this.services, ConversationDescriptor descriptor, this.sid)
      : super() {
    final attributes = descriptor.attributes ?? <String, dynamic>{};
    final createdBy = descriptor.createdBy;
    final dateCreated = parseTime(descriptor.dateCreated);
    final dateUpdated = parseTime(descriptor.dateUpdated);
    final friendlyName = descriptor.friendlyName;
    final lastReadMessageIndex = descriptor.lastConsumedMessageIndex;
    final uniqueName = descriptor.uniqueName;
    try {
      json.encode(attributes);
    } catch (e) {
      throw Exception('Attributes must be a valid JSON object.');
    }

    entityName = descriptor.channel;
    channelState = ConversationChannelState(
        uniqueName: uniqueName,
        attributes: attributes,
        createdBy: createdBy,
        dateCreated: dateCreated,
        dateUpdated: dateUpdated,
        friendlyName: friendlyName,
        lastReadMessageIndex: lastReadMessageIndex,
        notificationLevel: descriptor.notificationLevel);

    participantsEntity = Participants(
        conversation: this,
        syncClient: services.syncClient,
        session: services.session,
        users: services.users,
        participants: participants);
    participantsEntity.on(
        'participantJoined', (_) => emit('participantJoined'));
    participantsEntity.on('participantLeft', (_) => emit('participantLeft'));
    participantsEntity.on('participantUpdated',
        (args) => emit('participantUpdated', payload: args));
    messagesEntity = Messages(
        conversation: this,
        session: services.session,
        mcsClient: services.mcsClient,
        network: services.network,
        syncClient: services.syncClient);
    messagesEntity.on('messageAdded', (message) => _onMessageAdded(message));
    messagesEntity.on(
        'messageUpdated', (args) => emit('messageUpdated', payload: args));
    messagesEntity.on('messageRemoved', (_) => emit('messageRemoved'));
  }

  DataSource statusSource;
  Messages messagesEntity;
  Participants participantsEntity;
  Future entityPromise;
  String entityName;
  SyncDocument entity;
  String sid;
  ConversationServices services;
  ConversationChannelState channelState;
  Map<String, Participant> participants = {};

  String get uniqueName => channelState.uniqueName;
  ConversationStatus get status => channelState.status;
  String get friendlyName => channelState.friendlyName;
  DateTime get dateUpdated => channelState.dateUpdated;
  DateTime get dateCreated => channelState.dateCreated;
  String get createdBy => channelState.createdBy;
  Map<String, dynamic> get attributes => channelState.attributes;
  int get lastReadMessageIndex => channelState.lastReadMessageIndex;
  LastMessage get lastMessage => channelState.lastMessage;
  ConversationNotificationLevel get notificationLevel =>
      channelState.notificationLevel;
  ConversationLifecycleState get state => channelState.state;
/**
 * The Conversation's last message's information.
 * @typedef {Object} Conversation#LastMessage
 * @property [int] index - Message's index
 * @property [DateTime] dateCreated - Message's creation date
 */
  /// Load and Subscribe to this Conversation and do not subscribe to its Participants and Messages.
  /// This or _subscribeStreams will need to be called before any events on Conversation will fire.
  /// @returns {Promise}
  /// @private
  Future subscribe() {
    if (entityPromise != null) {
      return entityPromise;
    }
    return entityPromise = entityPromise ??
        services.syncClient
            .document(id: entityName, mode: OpenMode.openExisting)
            .then((entity) {
          entity = entity;
          entity.on('updated', (args) {
            update(args['data']);
          });
          entity.on('removed', (_) => emit('removed', payload: this));
          update(entity.data);
          return entity;
        }).onError((err, trace) {
          entity = null;
          entityPromise = null;
          if (services.syncClient.connectionState !=
              TwilsockState.disconnected) {
            // error('Failed to get conversation object', err);
          }
          // debug('ERROR: Failed to get conversation object', err);
          throw err;
        });
  }

  /// Load the attributes of this Conversation and instantiate its Participants and Messages.
  /// This or _subscribe will need to be called before any events on Conversation will fire.
  /// This will need to be called before any events on Participants or Messages will fire
  /// @returns {Promise}
  /// @private
  Future subscribeStreams() async {
    try {
      await subscribe();
      // trace('_subscribeStreams, entity.data=', entity.data);
      final messagesObjectName = entity.data['messages'];
      final rosterObjectName = entity.data['roster'];
      await Future.value([
        messagesEntity.subscribe(messagesObjectName),
        participantsEntity.subscribe(rosterObjectName)
      ]);
    } catch (err) {
      if (services.syncClient.connectionState != TwilsockState.disconnected) {
        // error('Failed to subscribe on conversation objects', sid, err);
      }
      // debug('ERROR: Failed to subscribe on conversation objects', sid, err);
      rethrow;
    }
  }

  /// Stop listening for and firing events on this Conversation.
  /// @returns {Promise}
  /// @private
  Future _unsubscribe() async {
    if (entity != null) {
      entity.close();
      entity = null;
      entityPromise = null;
    }
    return Future.value(
        [participantsEntity.unsubscribe(), messagesEntity.unsubscribe()]);
  }

  /// Set conversation status
  /// @private
  void setStatus(ConversationStatus status, DataSource source) {
    statusSource = source;
    if (channelState.status == status) {
      return;
    }
    channelState.status = status;
    if (status == ConversationStatus.joined) {
      subscribeStreams().onError((err, trace) {
        // debug('ERROR while setting conversation status ' + status, err);
        if (services.syncClient.connectionState != TwilsockState.disconnected) {
          throw err;
        }
      });
    } else if (entityPromise != null) {
      _unsubscribe().onError((err, trace) {
        // debug('ERROR while setting conversation status ' + status, err);
        if (services.syncClient.connectionState != TwilsockState.disconnected) {
          throw err;
        }
      });
    }
  }

  /// If conversation's status update source
  /// @private
  /// @return {Conversations.DataSource}
  // DataSource get statusSource =>
  //   statusSource;

  static void preprocessUpdate(
      Map<String, dynamic> update, String conversationSid) {
    try {
      if (update['attributes'] is String) {
        update['attributes'] = json.decode(update['attributes']);
      } else if (update['attributes']) {
        json.encode(update['attributes']);
      }
    } catch (e) {
      // warn('Retrieved malformed attributes from the server for conversation: ' + conversationSid);
      update['attributes'] = {};
    }
    try {
      if (update['dateCreated'] != null) {
        update['dateCreated'] = DateTime.tryParse(update['dateCreated']);
      }
    } catch (e) {
      // warn('Retrieved malformed dateCreated from the server for conversation: ' + conversationSid);
      update.remove(['dateCreated']);
    }
    try {
      if (update['dateUpdated'] != null) {
        update['dateUpdated'] = DateTime.tryParse(update['dateUpdated']);
      }
    } catch (e) {
      // warn('Retrieved malformed dateUpdated from the server for conversation: ' + conversationSid);
      update.remove('dateUpdated');
    }
    try {
      if (update['lastMessage'] != null && update['lastMessage']['timestamp']) {
        update['lastMessage']['timestamp'] =
            DateTime.tryParse(update['lastMessage']['timestamp']);
      }
    } catch (e) {
      // warn('Retrieved malformed lastMessage.timestamp from the server for conversation: ' + conversationSid);
      update['lastMessage'].remove('timestamp');
    }
  }

  /// Updates local conversation object with new values
  /// @private
  void update(Map<String, dynamic> update) {
    var _a, _b, _c, _d; //_e;
    // trace('_update', update);
    Conversation.preprocessUpdate(update, sid);
    final updateReasons = <ConversationUpdateReason>{};
    for (final key in update.keys) {
      final localKey = fieldMappings[key];
      if (localKey == null) {
        continue;
      }
      switch (localKey) {
        case FieldMappings.status:
          if (update['status'] == null ||
              update['status'] == 'unknown' ||
              channelState.status == update['status']) {
            break;
          }
          channelState.status = update['status'];
          updateReasons.add(localKeyToUpdateReason(localKey));
          break;
        case FieldMappings.attributes:
          if (channelState.attributes == update['attributes']) {
            break;
          }
          channelState.attributes = update['attributes'];
          updateReasons.add(localKeyToUpdateReason(localKey));
          break;
        case FieldMappings.lastConsumedMessageIndex:
          if (update['lastConsumedMessageIndex'] == null ||
              update['lastConsumedMessageIndex'] ==
                  channelState.lastReadMessageIndex) {
            break;
          }
          channelState.lastReadMessageIndex =
              update['lastConsumedMessageIndex'];
          updateReasons.add(ConversationUpdateReason.lastReadMessageIndex);
          break;
        case FieldMappings.lastMessage:
          if (channelState.lastMessage != null &&
              update['lastMessage'] == null) {
            channelState.lastMessage = null;
            updateReasons.add(localKeyToUpdateReason(localKey));
            break;
          }
          if (((_a = update['lastMessage']) == null || _a == null
                      ? null
                      : _a['index']) !=
                  null &&
              update['lastMessage']['index'] !=
                  channelState.lastMessage.index) {
            channelState.lastMessage.index = update['lastMessage']['index'];
            updateReasons.add(localKeyToUpdateReason(localKey));
          }
          if (((_b = update['lastMessage']) == null || _b == null
                      ? null
                      : _b['timestamp']) !=
                  null &&
              ((_d = (_c = channelState.lastMessage) == null || _c == null
                                  ? null
                                  : _c.dateCreated) ==
                              null ||
                          _d == null
                      ? null
                      : DateTime.tryParse(_d).millisecondsSinceEpoch) !=
                  DateTime.tryParse(update['lastMessage']['timestamp'])
                      .millisecondsSinceEpoch) {
            channelState.lastMessage.dateCreated =
                DateTime.tryParse(update['lastMessage']['timestamp']);
            updateReasons.add(localKeyToUpdateReason(localKey));
          }
          break;
        case FieldMappings.state:
          final state = update['state'];
          if (state != null) {
            state.dateUpdated = DateTime.tryParse(state['dateUpdated']);
          }
          if (channelState.state == state) {
            // todo
            break;
          }
          channelState.state = state;
          updateReasons.add(localKeyToUpdateReason(localKey));
          break;
        default:
          // final isDateTime = DateTime.tryParse(update[key]) != null; // todo here, by the name of the method, the value should be updated either in the state or in the conversation
          // final keysMatchAsDateTimes = isDateTime &&
          //     ((_e = channelState.dateUpdated) == null || _e == null
          //             ? null
          //             : _e).millisecondsSinceEpoch ==
          //         update[key].millisecondsSinceEpoch;
          // final keysMatchAsNonDateTimes =
          //     !isDateTime && this[localKey] == update[key];
          // if (keysMatchAsDateTimes || keysMatchAsNonDateTimes) {
          //   break;
          // }
          // channelState[localKey] = update[key];
          updateReasons.add(localKeyToUpdateReason(localKey));
      }
    }
    if (updateReasons.isNotEmpty) {
      emit('updated', payload: {
        'conversation': this,
        'updateReasons': [...updateReasons]
      });
    }
  }

  /// @private
  void _onMessageAdded(Message message) {
    for (var participant in participants.values) {
      if (participant.identity == message.author) {
        participant.endTyping();
        break;
      }
    }
    emit('messageAdded', payload: message);
  }

  /// Add a participant to the Conversation by its Identity.
  /// @param [String] identity - Identity of the Client to add
  /// @param {any} [attributes] Attributes to be attached to the participant
  /// @returns {Future<void>}
  Future add({String identity, Map<String, dynamic> attributes}) {
    return participantsEntity.add(identity, attributes);
  }

  /// Add a non-chat participant to the Conversation.
  ///
  /// @param [String] proxyAddress Proxy (Twilio) address of the participant
  /// @param [String] address User address of the participant
  /// @param {any} [attributes] Attributes to be attached to the participant
  /// @returns {Future<void>}
  Future<void> addNonChatParticipant(
      {String proxyAddress,
      String address,
      Map<String, dynamic> attributes = const <String, dynamic>{}}) {
    return participantsEntity.addNonChatParticipant(proxyAddress, address,
        attributes: attributes);
  }

  /// Advance Conversation's last read Message index to current read horizon.
  /// Rejects if User is not Participant of Conversation.
  /// Last read Message index is updated only if new index value is higher than previous.
  /// @param [int] index - Message index to advance to as last read
  /// @returns {Future<int>} resulting unread messages count in the conversation
  Future advanceLastReadMessageIndex(int index) async {
    await subscribeStreams();
    return services.readHorizon.advanceLastReadMessageIndexForConversation(
        sid, index, lastReadMessageIndex);
  }

  /// Delete the Conversation and unsubscribe from its events.
  /// @returns {Future<Conversation>}
  Future<Conversation> delete() async {
    await services.session.addCommand('destroyChannel', {'channelSid': sid});
    return this;
  }

  /// Get the custom attributes of this Conversation.
  /// @returns {Future<any>} attributes of this Conversation
  Future getAttributes() async {
    await subscribe();
    return attributes;
  }

  /// Returns messages from conversation using paginator interface.
  /// @param [int] [pageSize=30] Number of messages to return in single chunk
  /// @param [int] [anchor] - Index of newest Message to fetch. From the end by default
  /// @param {('backwards'|'forward')} [direction=backwards] - Query direction. By default it query backwards
  ///                                                          from newer to older. 'forward' will query in opposite direction
  /// @returns {Future<Paginator<Message>>} page of messages
  Future getMessages(int pageSize, {String anchor, String direction}) async {
    await subscribeStreams();
    return messagesEntity.getMessages(pageSize,
        anchor: anchor, direction: direction);
  }

  /// Get a list of all Participants joined to this Conversation.
  /// @returns {Future<Participant[]>}
  Future<List<Participant>> getParticipants() async {
    await subscribeStreams();
    return participantsEntity.getParticipants();
  }

  /// Get conversation participants count.
  /// <br/>
  /// This method is semi-realtime. This means that this data will be eventually correct,
  /// but will also possibly be incorrect for a few seconds. The Conversation system does not
  /// provide real time events for counter values changes.
  /// <br/>
  /// So this is quite useful for any UI badges, but is not recommended
  /// to build any core application logic based on these counters being accurate in real time.
  /// @returns {Future<int>}
  Future getParticipantsCount() async {
    final links = await services.session.getSessionLinks();
    final url = UriBuilder(links.publicChannelsUrl).addPathSegment(sid).build();
    final response = await services.network.get(url);
    return response.data.members_count;
  }

  /// Get a Participant by its SID.
  /// @param [String] participantSid - Participant sid
  /// @returns {Future<Participant>}
  Future getParticipantBySid(participantSid) {
    return participantsEntity.getParticipantBySid(participantSid);
  }

  /// Get a Participant by its identity.
  /// @param [String] identity - Participant identity
  /// @returns {Future<Participant>}
  Future getParticipantByIdentity(String identity) {
    return participantsEntity.getParticipantByIdentity(identity);
  }

  /// Get total message count in a conversation.
  /// <br/>
  /// This method is semi-realtime. This means that this data will be eventually correct,
  /// but will also possibly be incorrect for a few seconds. The Conversations system does not
  /// provide real time events for counter values changes.
  /// <br/>
  /// So this is quite useful for any UI badges, but is not recommended
  /// to build any core application logic based on these counters being accurate in real time.
  /// @returns {Future<int>}
  Future getMessagesCount() async {
    final links = await services.session.getSessionLinks();
    final url = UriBuilder(links.publicChannelsUrl).addPathSegment(sid).build();
    final response = await services.network.get(url);
    return response.data['messages_count'];
  }

  /// Get unread messages count for the User if they are a Participant of this Conversation.
  /// Rejects if the User is not a Participant of the Conversation.
  /// <br/>
  /// Use this method to obtain the int of unread messages together with
  /// updateLastReadMessageIndex() instead of relying on the
  /// Message indices which may have gaps. See Message.index for details.
  /// <br/>
  /// This method is semi-realtime. This means that this data will be eventually correct,
  /// but will also possibly be incorrect for a few seconds. The Chat system does not
  /// provide real time events for counter values changes.
  /// <br/>
  /// This is quite useful for any “unread messages count” badges, but is not recommended
  /// to build any core application logic based on these counters being accurate in real time.
  /// @returns {Future<int|null>}
  Future getUnreadMessagesCount() async {
    final links = await services.session.getSessionLinks();
    final url = UriBuilder(links.myChannelsUrl)
        .addQueryParam('ChannelSid', value: sid)
        .build();
    final response = await services.network.get(url);
    if (response.data['channels'].length != null &&
        response.data['channels'][0]['channel_sid'] == sid) {
      if (response.data['channels'][0]['unread_messages_count'] != null) {
        return response.data['channels'][0]['unread_messages_count'];
      }
      return null;
    }
    throw Exception('Conversation is not in user conversations list');
  }

  /// Join the Conversation and subscribe to its events.
  /// @returns {Future<Conversation>}
  Future<Conversation> join() async {
    await services.session.addCommand('joinChannelV2', {'channelSid': sid});
    return this;
  }

  /// Leave the Conversation.
  /// @returns {Future<Conversation>}
  Future<Conversation> leave() async {
    if (channelState.status == ConversationStatus.joined) {
      await services.session.addCommand('leaveChannel', {'channelSid': sid});
    }
    return this;
  }

  /// Remove a Participant from the Conversation. When a String is passed as the argument, it will assume that the String is an identity.
  /// @param {String|Participant} participant - identity or participant object to remove
  /// @returns {Future<void>}
  Future<void> removeParticipant(
      {String identity, Participant participant}) async {
    if (participant != null) {
      await participantsEntity.removeBySid(participant.sid);
      return;
    }
    await participantsEntity.removeByIdentity(identity);
  }

  /// Send a Message in the Conversation.
  /// @param {String|FormData|Conversation#SendMediaOptions|null} message - The message body for text message,
  /// FormData or MediaOptions for media content. Sending FormData supported only with browser engine
  /// @param {any} [messageAttributes] - attributes for the message
  /// @param {Conversation#SendEmailOptions} [emailOptions] - email options for the message
  /// @returns {Future<int>} new Message's index in the Conversation's messages list
  Future sendMessage(dynamic message, messageAttributes, String subject) async {
    if (message is String || message == null) {
      final response = await messagesEntity.send(message,
          attributes: messageAttributes, subject: subject);
      return response.messageId;
    }
    final response = await messagesEntity.sendMedia(message,
        attributes: messageAttributes, subject: subject);
    return response.messageId;
  }

  /// Set last read Conversation's Message index to last known Message's index in this Conversation.
  /// @returns {Future<int>} resulting unread messages count in the conversation
  Future<int> setAllMessagesRead() async {
    await subscribeStreams();
    final messagesPage = await getMessages(1);
    if (messagesPage.items.length > 0) {
      return advanceLastReadMessageIndex(messagesPage.items[0].index);
    }
    return Future.value(0);
  }

  /// Set all messages in the conversation unread.
  /// @returns {Future<int>} resulting unread messages count in the conversation
  Future<int> setAllMessagesUnread() async {
    await subscribeStreams();
    return services.readHorizon
        .updateLastReadMessageIndexForConversation(sid, null);
  }

  /// Set User Notification level for this conversation.
  /// @param {Conversation#NotificationLevel} notificationLevel - The new user notification level
  /// @returns {Future<void>}
  Future<void> setUserNotificationLevel(notificationLevel) async {
    await services.session.addCommand('editNotificationLevel',
        {'channelSid': sid, notificationLevel: notificationLevel});
  }

  /// Send a notification to the server indicating that this Client is currently typing in this Conversation.
  /// Typing ended notification is sent after a while automatically, but by calling again this method you ensure typing ended is not received.
  /// @returns {Future<void>}
  Future<void> typing() {
    return services.typingIndicator.send(sid);
  }

  /// Update the Conversation's attributes.
  /// @param {any} attributes - The new attributes object
  /// @returns {Future<Conversation>}
  Future<Conversation> updateAttributes(Map<String, dynamic> attributes) async {
    await services.session.addCommand('editAttributes',
        {'channelSid': sid, 'attributes': json.encode(attributes)});
    return this;
  }

  /// Update the Conversation's friendlyName.
  /// @param {String|null} name - The new Conversation friendlyName
  /// @returns {Future<Conversation>}
  Future<Conversation> updateFriendlyName(String name) async {
    if (channelState.friendlyName != name) {
      await services.session.addCommand(
          'editFriendlyName', {'channelSid': sid, friendlyName: name});
    }
    return this;
  }

  /// Set Conversation's last read Message index to current read horizon.
  /// @param {Number|null} index - Message index to set as last read.
  /// If null provided, then the behavior is identical to {@link Conversation#setAllMessagesUnread}
  /// @returns {Future<int>} resulting unread messages count in the conversation
  Future<int> updateLastReadMessageIndex(int index) async {
    await subscribeStreams();
    return services.readHorizon
        .updateLastReadMessageIndexForConversation(sid, index);
  }

  /// Update the Conversation's unique name.
  /// @param {String|null} uniqueName - New unique name for the Conversation. Setting unique name to null removes it.
  /// @returns {Future<Conversation>}
  Future<Conversation> updateUniqueName(String uniqueName) async {
    if (channelState.uniqueName != uniqueName) {
      await services.session.addCommand(
          'editUniqueName', {'channelSid': sid, uniqueName: uniqueName});
    }
    return this;
  }
}
/**
 * Fired when a Participant has joined the Conversation.
 * @event Conversation#participantJoined
 * @type {Participant}
 */
/**
 * Fired when a Participant has left the Conversation.
 * @event Conversation#participantLeft
 * @type {Participant}
 */
/**
 * Fired when a Participant's fields has been updated.
 * @event Conversation#participantUpdated
 * @type {Object}
 * @property {Participant} participant - Updated Participant
 * @property {Participant#UpdateReason[]} updateReasons - List of Participant's updated event reasons
 */
/**
 * Fired when a new Message has been added to the Conversation.
 * @event Conversation#messageAdded
 * @type {Message}
 */
/**
 * Fired when Message is removed from Conversation's message list.
 * @event Conversation#messageRemoved
 * @type {Message}
 */
/**
 * Fired when an existing Message's fields are updated with new values.
 * @event Conversation#messageUpdated
 * @type {Object}
 * @property {Message} message - Updated Message
 * @property {Message#UpdateReason[]} updateReasons - List of Message's updated event reasons
 */
/**
 * Fired when a Participant has stopped typing.
 * @event Conversation#typingEnded
 * @type {Participant}
 */
/**
 * Fired when a Participant has started typing.
 * @event Conversation#typingStarted
 * @type {Participant}
 */
/**
 * Fired when a Conversation's attributes or metadata have been updated.
 * @event Conversation#updated
 * @type {Object}
 * @property {Conversation} conversation - Updated Conversation
 * @property {Conversation#UpdateReason[]} updateReasons - List of Conversation's updated event reasons
 */
/**
 * Fired when the Conversation was destroyed or currently logged in User has left private Conversation
 * @event Conversation#removed
 * @type {Conversation}
 */ ///
