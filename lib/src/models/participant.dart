import 'dart:async';
import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/contexts/users.dart';
import 'package:twilio_conversations/src/enum/conversations/participant_type.dart';
import 'package:twilio_conversations/src/enum/conversations/user_update_reason.dart';
import 'package:twilio_conversations/src/models/conversation.dart';
import 'package:twilio_conversations/src/models/user.dart';

import '../core/session/session.dart';

void clearTimeout(Timer timer) {
  timer.cancel();
}

ParticipantType participantTypeFromString(String type) {
  switch (type) {
    case 'chat':
      return ParticipantType.chat;
    case 'sms':
      return ParticipantType.sms;
    case 'whatsapp':
      return ParticipantType.whatsapp;
  }
  return null;
}

class ParticipantState {
  ParticipantState(
      {String dateCreated,
      String dateUpdated,
      this.sid,
      this.isTyping = false,
      this.identity,
      this.roleSid,
      String lastConsumptionTimestamp,
      this.lastReadMessageIndex,
      String type = 'chat',
      this.userInfo,
      String attributes})
      : dateCreated = DateTime.tryParse(dateCreated),
        dateUpdated = DateTime.tryParse(dateUpdated),
        type = participantTypeFromString(type),
        lastReadTimestamp = DateTime.tryParse(lastConsumptionTimestamp),
        attributes = parseAttributes(attributes);
  Map<String, dynamic> attributes;
  DateTime dateCreated;
  DateTime dateUpdated;
  String sid;
  Timer typingTimeout;
  bool isTyping;
  String identity;
  String roleSid;
  int lastReadMessageIndex;
  DateTime lastReadTimestamp;
  ParticipantType type;
  String userInfo;
}

/// @classdesc A Participant represents a remote Client in a Conversation.
/// @property {any} attributes - Object with custom attributes for Participant
/// @property {Conversation} conversation - The Conversation the remote Client is a Participant of
/// @property [DateTime] dateCreated - The DateTime this Participant was created
/// @property [DateTime] dateUpdated - The DateTime this Participant was last updated
/// @property [String] identity - The identity of the remote Client
/// @property [bool] isTyping - Whether or not this Participant is currently typing
/// @property {Number|null} lastReadMessageIndex - Latest read Message index by this Participant.
/// Note that just retrieving messages on a client endpoint does not mean that messages are read,
/// please consider reading about [Read Horizon feature]{@link https://www.twilio.com/docs/api/chat/guides/consumption-horizon}
/// to find out how to mark messages as read.
/// @property [DateTime] lastReadTimestamp - DateTime when Participant has updated his read horizon
/// @property [String] sid - The server-assigned unique identifier for the Participant
/// @property {Participant#Type} type - The type of Participant
/// @fires Participant#typingEnded
/// @fires Participant#typingStarted
/// @fires Participant#updated
class Participant extends Stendo {
  ///The update reason for <code>updated</code> event emitted on Participant
  ///@typedef {('attributes' | 'dateCreated' | 'dateUpdated' | 'roleSid' |
  /// 'lastReadMessageIndex' | 'lastReadTimestamp')} Participant#UpdateReason
  ///
  /// The type of Participant
  /// @typedef {('chat' | 'sms' | 'whatsapp')} Participant#Type
  Participant(
      {this.conversation,
      Map<String, dynamic> data,
      String sid,
      this.users,
      this.session})
      : super() {
    state = ParticipantState(
        attributes: data['attributes'],
        dateCreated: data['dateCreated'],
        dateUpdated: data['dateUpdated'],
        sid: sid,
        identity: data['identity'],
        roleSid: data['roleSid'],
        lastReadMessageIndex: data['lastConsumedMessageIndex'],
        lastConsumptionTimestamp: data['lastConsumptionTimestamp'],
        type: data['type'],
        userInfo: data['userInfo']);

    if (data['identity'] == null && data['type'] == null) {
      throw Exception(
          'Received invalid Participant object from server: Missing identity or type of Participant.');
    }
  }

  Conversation conversation;
  Session session;
  Users users;
  ParticipantState state;

  String get sid => state.sid;
  Map<String, dynamic> get attributes => state.attributes;
  DateTime get dateCreated => state.dateCreated;
  DateTime get dateUpdated => state.dateUpdated;
  String get identity => state.identity;
  bool get isTyping => state.isTyping;
  int get lastReadMessageIndex => state.lastReadMessageIndex;
  DateTime get lastReadTimestamp => state.lastReadTimestamp;
  String get roleSid => state.roleSid;
  ParticipantType get type => state.type;

  /// Private method used to start or reset the typing indicator timeout (with event emitting)
  /// @private
  Participant startTyping(int timeout) {
    clearTimeout(state.typingTimeout);
    state.isTyping = true;
    emit('typingStarted', payload: this);
    conversation.emit('typingStarted', payload: this);
    state.typingTimeout =
        Timer(Duration(milliseconds: timeout), () => endTyping());
    return this;
  }

  /// Private method used to stop typing indicator (with event emitting)
  /// @private
  void endTyping() {
    if (state.typingTimeout == null) {
      return;
    }
    state.isTyping = false;
    emit('typingEnded', payload: this);
    conversation.emit('typingEnded', payload: this);
    clearTimeout(state.typingTimeout);
    state.typingTimeout = null;
  }

  /// Private method used update local object's property roleSid with new value
  /// @private
  Participant update(Map<String, dynamic> data) {
    final updateReasons = [];
    final updateAttributes = parseAttributes(
      data['attributes'],
    );
    if (data['attributes'] != null && !(state.attributes == updateAttributes)) {
      state.attributes = updateAttributes;
      updateReasons.add(UserUpdateReason.attributes);
    }
    final updatedDateTimeUpdated = DateTime.tryParse(data['dateUpdated']);
    if (data['dateUpdated'] != null &&
        state.dateUpdated != null &&
        updatedDateTimeUpdated.millisecondsSinceEpoch !=
            state.dateUpdated.millisecondsSinceEpoch) {
      state.dateUpdated = updatedDateTimeUpdated;
      updateReasons.add(UserUpdateReason.dateUpdated);
    }
    final updatedDateTimeCreated = DateTime.tryParse(data['dateCreated']);
    if (data['dateCreated'] != null &&
        state.dateCreated != null &&
        updatedDateTimeCreated.millisecondsSinceEpoch !=
            state.dateCreated.millisecondsSinceEpoch) {
      state.dateCreated = updatedDateTimeCreated;
      updateReasons.add(UserUpdateReason.dateCreated);
    }
    if (data['roleSid'] != null && state.roleSid != data['roleSid']) {
      state.roleSid = data['roleSid'];
      updateReasons.add(UserUpdateReason.roleSid);
    }
    if ((data['lastConsumedMessageIndex'] is int) ||
        data['lastConsumedMessageIndex'] == null &&
            state.lastReadMessageIndex != data['lastConsumedMessageIndex']) {
      state.lastReadMessageIndex = data['lastConsumedMessageIndex'];
      updateReasons.add(UserUpdateReason.lastReadMessageIndex);
    }
    if (data['lastConsumptionTimestamp'] != null) {
      final lastReadTimestamp =
          DateTime.tryParse(data['lastConsumptionTimestamp']);
      if (state.lastReadTimestamp == null ||
          state.lastReadTimestamp.millisecondsSinceEpoch !=
              lastReadTimestamp.millisecondsSinceEpoch) {
        state.lastReadTimestamp = lastReadTimestamp;
        updateReasons.add(UserUpdateReason.lastReadTimestamp);
      }
    }
    if (updateReasons.isNotEmpty) {
      emit('updated',
          payload: {'participant': this, 'updateReasons': updateReasons});
    }
    return this;
  }

  /// Gets User for this participant and subscribes to it. Supported only for <code>chat</code> type of Participants
  /// @returns {Future<User>}
  Future getUser() {
    if (type != ParticipantType.chat) {
      throw Exception(
          'Getting User is not supported for this Participant type: ' +
              type.toString());
    }
    return users.getUser(state.identity, entityName: state.userInfo);
  }

  /// Remove Participant from the Conversation.
  /// @returns {Future<void>}
  Future remove() async {
    return await conversation.removeParticipant(participant: this);
  }

  /// Edit participant attributes.
  /// @param {any} attributes new attributes for Participant.
  /// @returns {Future<Participant>}
  Future updateAttributes(attributes) async {
    await session.addCommand('editMemberAttributes', {
      'channelSid': conversation.sid,
      'memberSid': sid,
      attributes: json.encode(attributes)
    });
    return this;
  }
}
/**
 * Fired when Participant started to type.
 * @event Participant#typingStarted
 * @type {Participant}
 */
/**
 * Fired when Participant ended to type.
 * @event Participant#typingEnded
 * @type {Participant}
 */
/**
 * Fired when Participant's fields has been updated.
 * @event Participant#updated
 * @type {Object}
 * @property {Participant} participant - Updated Participant
 * @property {Participant#UpdateReason[]} updateReasons - List of Participant's updated event reasons
 */
