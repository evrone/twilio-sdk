import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/enum/sync/open_mode.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_map/sync_map.dart';

import '../core/session/session.dart';
import '../models/conversation.dart';
import '../models/participant.dart';
import 'users.dart';

/// @classdesc Represents the collection of participants for the conversation
/// @fires Participants#participantJoined
/// @fires Participants#participantLeft
/// @fires Participants#participantUpdated
class Participants extends Stendo {
  Participants(
      {this.conversation,
      this.syncClient,
      this.session,
      this.users,
      this.participants})
      : super();

  Map<String, Participant> participants;
  Session session;
  SyncClient syncClient;
  Users users;
  Conversation conversation;

  Future<SyncMap> rosterEntityPromise;

  Future unsubscribe() async {
    if (rosterEntityPromise != null) {
      final entity = await rosterEntityPromise;
      entity.close();
      rosterEntityPromise = null;
    }
  }

  Future<SyncMap> subscribe(String rosterObjectName) {
    return rosterEntityPromise = rosterEntityPromise ??
        syncClient
            .map(id: rosterObjectName, mode: OpenMode.openExisting)
            .then((rosterMap) {
          rosterMap.on('itemAdded', (args) {
            // debug(conversation.sid + ' itemAdded: ' + args.item.key);
            final participant =
                upsertParticipant(args['item'].key, args['item'].data);

            emit('participantJoined', payload: participant);
          });
          rosterMap.on('itemRemoved', (args) {
            // debug(conversation.sid + ' itemRemoved: ' + args.key);
            final participantSid = args['key'];
            if (!participants.containsKey(participantSid)) {
              return;
            }
            final leftParticipant = participants[participantSid];
            participants.remove(participantSid);
            emit('participantLeft', payload: leftParticipant);
          });
          rosterMap.on('itemUpdated', (args) {
            // debug(conversation.sid + ' itemUpdated: ' + args.item.key);
            upsertParticipant(args['item'].key, args['item'].data);
          });
          final participantsPromises = [];
          final that = this;
          final rosterMapHandler = (paginator) {
            paginator.items.forEach((item) {
              participantsPromises
                  .add(that.upsertParticipant(item.key, item.data));
            });
            return paginator.hasNextPage ? paginator.nextPage() : null;
          };

          final paginator = rosterMap.getItems();
          rosterMapHandler(paginator);
          participantsPromises.forEach((promise) async {
            await promise;
          });
          return rosterMap;
        });
    //     .onError((err) {
    // rosterEntityPromise = null;
    // if (syncClient.connectionState != 'disconnected') {
    // // error('Failed to get roster object for conversation', conversation.sid, err);
    // }
    // // debug('ERROR: Failed to get roster object for conversation', conversation.sid, err);
    // throw err;
    // });
  }

  Participant upsertParticipant(
      String participantSid, Map<String, dynamic> data) {
    var participant = participants[participantSid];
    if (participant != null) {
      return participant.update(data);
    }
    participant = Participant(
        session: session,
        conversation: conversation,
        data: data,
        sid: participantSid);
    participants[participantSid] = participant;
    participant.on(
        'updated', (args) => emit('participantUpdated', payload: args));
    return participant;
  }

  /// @returns {Future<List<Participant>>} returns list of participants {@see Participant}
  Future<List<Participant>> getParticipants() async {
    await rosterEntityPromise;
    final participants = [];
    this
        .participants
        .values
        .forEach((participant) => participants.add(participant));
    return participants;
  }

  /// Get participant by SID from conversation
  /// @returns {Future<Participant>}
  Future<Participant> getParticipantBySid(String participantSid) async {
    await rosterEntityPromise;
    final participant = participants[participantSid];
    if (participant == null) {
      throw Exception(
          'Participant with SID ' + participantSid + ' was not found');
    }
    return participant;
  }

  /// Get participant by identity from conversation
  /// @returns {Future<Participant>}
  Future<Participant> getParticipantByIdentity(identity) async {
    var foundParticipant;
    await rosterEntityPromise;

    participants.values.forEach((participant) {
      if (participant.identity == identity) {
        foundParticipant = participant;
      }
    });
    if (foundParticipant == null) {
      throw Exception(
          'Participant with identity ' + identity + ' was not found');
    }
    return foundParticipant;
  }

  /// Add a chat participant to the conversation
  /// @returns {Future<any>}
  Future add(String identity, Map<String, dynamic> attributes) {
    return session.addCommand('addMemberV2', {
      'channelSid': conversation.sid,
      'attributes': json.encode(attributes),
      'username': identity
    });
  }

  /// Add a non-chat participant to the conversation.
  ///
  /// @param proxyAddress
  /// @param address
  /// @param attributes
  /// @returns {Future<any>}
  Future addNonChatParticipant(proxyAddress, address,
      {Map<String, dynamic> attributes = const <String, dynamic>{}}) {
    return session.addCommand('addNonChatParticipant', {
      'conversationSid': conversation.sid,
      'proxyAddress': proxyAddress,
      'attributes': json.encode(attributes),
      'address': address
    });
  }

  /// Invites user to the conversation
  /// User can choose either to join or not
  /// @returns {Future<any>}
  Future invite(String identity) {
    return session.addCommand(
        'inviteMember', {'channelSid': conversation.sid, 'username': identity});
  }

  /// Remove participant from conversation by Identity
  /// @returns {Future<any>}
  Future removeByIdentity(String identity) {
    return session.addCommand(
        'removeMember', {'channelSid': conversation.sid, 'username': identity});
  }

  /// Remove participant from conversation by sid
  /// @returns {Future<any>}
  Future removeBySid(String sid) {
    return session.addCommand(
        'removeMember', {'channelSid': conversation.sid, 'memberSid': sid});
  }
}
/**
 * Fired when participant joined conversation
 * @event Participants#participantJoined
 * @type {Participant}
 */
/**
 * Fired when participant left conversation
 * @event Participants#participantLeft
 * @type {Participant}
 */
/**
 * Fired when participant updated
 * @event Participants#participantUpdated
 * @type {Object}
 * @property {Participant} participant - Updated Participant
 * @property {Participant#UpdateReason[]} updateReasons - List of Participant's updated event reasons
 */
