import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/core/network.dart';
import 'package:twilio_conversations/src/enum/conversations/message_type.dart';
import 'package:twilio_conversations/src/enum/conversations/message_update_reasons.dart';
import 'package:twilio_conversations/src/models/conversation.dart';
import 'package:twilio_conversations/src/models/media.dart';
import 'package:twilio_conversations/src/models/user.dart';
import 'package:twilio_conversations/src/services/delivery/aggregateddeliveryreceipt.dart';
import 'package:twilio_conversations/src/services/router/client.dart';
import 'package:twilio_conversations/src/utils/rest_paginator.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

import '../core/session/session.dart';
import '../services/delivery/detaileddeliveryreceipt.dart';
import 'participant.dart';

MessageType messageTypeFromString(String type) {
  switch (type) {
    case 'text':
      return MessageType.text;
    case 'media':
      return MessageType.media;
  }
  return null;
}

class MessageState {
  MessageState(
      {this.sid,
      String type = 'text',
      String dateUpdated,
      String attributes,
      this.body,
      this.participantSid,
      this.index,
      this.aggregatedDeliveryReceipt,
      this.author,
      String timestamp,
      this.lastUpdatedBy,
      this.media,
      this.subject})
      : type = messageTypeFromString(type),
        dateUpdated = DateTime.tryParse(dateUpdated),
        timestamp = DateTime.tryParse(timestamp),
        attributes = parseAttributes(attributes);
  String sid;
  int index;
  String author;
  String subject;
  String body;
  DateTime timestamp;
  DateTime dateUpdated;
  String lastUpdatedBy;
  Map<String, dynamic> attributes;
  MessageType type;
  Media media;
  String participantSid;
  AggregatedDeliveryReceipt aggregatedDeliveryReceipt;
}

/// @classdesc A Message represents a Message in a Conversation.
/// @property [String] author - The name of the user that sent Message
/// @property {String|null} subject - Message subject. Used only in email conversations
/// @property [String] body - The body of the Message. Is null if Message is Media Message
/// @property {any} attributes - Message custom attributes
/// @property [Conversation] conversation - Conversation Message belongs to
/// @property [DateTime] dateCreated - When Message was created
/// @property [DateTime] dateUpdated - When Message was updated
/// @property [int] index - Index of Message in the Conversation's messages list
///  By design of the conversations system the message indices may have arbitrary gaps between them,
///  that does not necessarily mean they were deleted or otherwise modified - just that
///  messages may have non-contiguous indices even if they are sent immediately one after another.
///
///  Trying to use indices for some calculations is going to be unreliable.
///
///  To calculate the int of unread messages it is better to use the read horizon API.
///  See {@link Conversation#getUnreadMessagesCount} for details.
///
/// @property [String] lastUpdatedBy - Identity of the last user that updated Message
/// @property [Media] media - Contains Media information (if present)
/// @property [String] participantSid - Authoring Participant's server-assigned unique identifier
/// @property [String] sid - The server-assigned unique identifier for Message
/// @property {'text' | 'media'} type - Type of message: 'text' or 'media'
/// @property {AggregatedDeliveryReceipt | null} aggregatedDeliveryReceipt - Aggregated information about
///   Message delivery statuses across all {@link Participant}s of a {@link Conversation}.
/// @fires Message#updated
class Message extends Stendo {
  /// The update reason for <code>updated</code> event emitted on Message
  /// @typedef {('body' | 'lastUpdatedBy' | 'dateCreated' | 'dateUpdated' | 'attributes' | 'author' |
  ///   'deliveryReceipt' | 'subject')} Message#UpdateReason
  Message(
      {this.conversation,
      this.session,
      this.mcsClient,
      this.network,
      int index,
      Map<String, dynamic> data,
      MessageState prevState}) {
    if (prevState != null) {
      state = prevState;
    } else if (data != null) {
      state = MessageState(
          sid: data['sid'],
          index: index,
          author: data['author'],
          subject: data['subject'],
          body: data['text'],
          timestamp: data['timestamp'],
          dateUpdated: data['dateUpdated'],
          lastUpdatedBy: data['lastUpdatedBy'],
          attributes: data['attributes'],
          type: data['type'],
          media: data['type'] == media && data['media'] != null
              ? Media(
                  data: data['media'],
                  services: MediaServices(mcsClient: mcsClient))
              : null,
          participantSid: data['memberSid'],
          aggregatedDeliveryReceipt: data['delivery'] != null
              ? AggregatedDeliveryReceipt(data['delivery'])
              : null);
    }
  }

  Conversation conversation;
  Session session;
  McsClient mcsClient;
  ConversationNetwork network;
  MessageState state;

  String get sid => state.sid;
  String get author => state.author;
  String get subject => state.subject;
  String get body {
    if (type == MessageType.media) {
      return null;
    }
    return state.body;
  }

  DateTime get dateUpdated => state.dateUpdated;
  int get index => state.index;
  String get lastUpdatedBy => state.lastUpdatedBy;
  DateTime get dateCreated => state.timestamp;
  Map<String, dynamic> get attributes => state.attributes;
  MessageType get type => state.type;
  Media get media => state.media;
  String get participantSid => state.participantSid;
  AggregatedDeliveryReceipt get aggregatedDeliveryReceipt =>
      state.aggregatedDeliveryReceipt;
  void update(Map<String, dynamic> data) {
    final updateReasons = [];
    if ((data['text'] != null) && data['text'] != state.body) {
      state.body = data['text'];
      updateReasons.add(MessageUpdateReasons.body);
    }
    if (data['subject'] != null && data['subject'] != state.subject) {
      state.subject = data['subject'];
      updateReasons.add(MessageUpdateReasons.subject);
    }
    if (data['lastUpdatedBy'] != null &&
        data['lastUpdatedBy'] != state.lastUpdatedBy) {
      state.lastUpdatedBy = data['lastUpdatedBy'];
      updateReasons.add(MessageUpdateReasons.lastUpdatedBy);
    }
    if (data['author'] != null && data['author'] != state.author) {
      state.author = data['author'];
      updateReasons.add(MessageUpdateReasons.author);
    }
    if (data['dateUpdated'] != null &&
        state.dateUpdated != null &&
        DateTime.tryParse(data['dateUpdated']).millisecondsSinceEpoch !=
            (state.dateUpdated.millisecondsSinceEpoch)) {
      state.dateUpdated = DateTime.tryParse(data['dateUpdated']);
      updateReasons.add(MessageUpdateReasons.dateUpdated);
    }
    if (data['timestamp'] != null &&
        state.timestamp != null &&
        DateTime.tryParse(data['timestamp']).millisecondsSinceEpoch !=
            (state.timestamp.millisecondsSinceEpoch)) {
      state.timestamp = DateTime.tryParse(data['timestamp']);
      updateReasons.add(MessageUpdateReasons.dateCreated);
    }
    final updatedAttributes = parseAttributes(data['attributes']);
    if (!(state.attributes == updatedAttributes)) {
      state.attributes = updatedAttributes;
      updateReasons.add(MessageUpdateReasons.attributes);
    }
    final updatedAggregatedDelivery = data['delivery'];
    final currentAggregatedDelivery = state.aggregatedDeliveryReceipt;
    final isUpdatedAggregateDeliveryValid = updatedAggregatedDelivery != null &&
        updatedAggregatedDelivery['total'] != null &&
        updatedAggregatedDelivery['delivered'] != null &&
        updatedAggregatedDelivery['failed'] != null &&
        updatedAggregatedDelivery['read'] != null &&
        updatedAggregatedDelivery['sent'] != null &&
        updatedAggregatedDelivery['undelivered'] != null;
    if (isUpdatedAggregateDeliveryValid) {
      if (currentAggregatedDelivery == null) {
        state.aggregatedDeliveryReceipt =
            AggregatedDeliveryReceipt(updatedAggregatedDelivery);
        updateReasons.add(MessageUpdateReasons.deliveryReceipt);
      } else if (!currentAggregatedDelivery
          .isEquals(updatedAggregatedDelivery)) {
        currentAggregatedDelivery.update(updatedAggregatedDelivery);
        updateReasons.add(MessageUpdateReasons.deliveryReceipt);
      }
    }
    if (updateReasons.isNotEmpty) {
      emit('updated',
          payload: {'message': this, 'updateReasons': updateReasons});
    }
  }

  /// Get Participant who is author of the Message
  /// @returns {Future<Participant>}
  Future getParticipant() async {
    Participant participant;
    if (state.participantSid != null) {
      try {
        participant = await conversation.getParticipantBySid(participantSid);
      } catch (e) {
        // debug('Participant with sid '' + participantSid + '' not found for message ' + sid);
        return null;
      }
    }
    if (participant == null && state.author != null) {
      try {
        participant = await conversation.getParticipantByIdentity(state.author);
      } catch (e) {
        // debug('Participant with identity '' + author + '' not found for message ' + sid);
        return null;
      }
    }
    if (participant != null) {
      return participant;
    }
    var errorMesage = 'Participant with ';
    if (state.participantSid != null) {
      errorMesage += 'SID \'' + state.participantSid + '\' ';
    }
    if (state.author != null) {
      if (state.participantSid != null) {
        errorMesage += 'or ';
      }
      errorMesage += 'identity \'' + state.author + '\' ';
    }
    if (errorMesage == 'Participant with ') {
      errorMesage = 'Participant ';
    }
    errorMesage += 'was not found';
    throw Exception(errorMesage);
  }

  /// Get delivery receipts of the message
  /// @returns {Future<DetailedDeliveryReceipt[]>}
  Future getDetailedDeliveryReceipts() async {
    var paginator = await _getDetailedDeliveryReceiptsPaginator();
    var detailedDeliveryReceipts = [];
    while (true) {
      detailedDeliveryReceipts = [
        ...detailedDeliveryReceipts,
        ...paginator.items
      ];
      if (!paginator.hasNextPage) {
        break;
      }
      paginator = await paginator.nextPage();
    }
    return detailedDeliveryReceipts;
  }

  /// Remove the Message.
  /// @returns {Future<Message>}
  Future remove() async {
    await session.addCommand('deleteMessage',
        {'channelSid': conversation.sid, 'messageIdx': index.toString()});
    return this;
  }

  /// Edit message body.
  /// @param [String] body - new body of Message.
  /// @returns {Future<Message>}
  Future updateBody(String body) async {
    await session.addCommand('editMessage', {
      'channelSid': conversation.sid,
      'messageIdx': index.toString(),
      'text': body
    });
    return this;
  }

  /// Edit message attributes.
  /// @param {any} attributes new attributes for Message.
  /// @returns {Future<Message>}
  Future updateAttributes(Map<String, dynamic> attributes) async {
    await session.addCommand('editMessageAttributes', {
      'channelSid': conversation.sid,
      'messageIdx': index,
      attributes: json.encode(attributes)
    });
    return this;
  }

  Future _getDetailedDeliveryReceiptsPaginator(
      {String pageToken, int pageSize}) async {
    final links = await session.getSessionLinks();
    final messagesReceiptsUrl = links.messagesReceiptsUrl
        .replaceFirst('%s', conversation.sid)
        .replaceFirst('%s', sid);
    final url = UriBuilder(messagesReceiptsUrl)
        .addQueryParam('PageToken', value: pageToken)
        .addQueryParam('PageSize', value: pageSize)
        .build();
    final response = await network.get(url);
    return RestPaginator(
        items: response.data['delivery_receipts'].map(
            (x) => DetailedDeliveryReceipt(
                messageSid: x['message_sid'],
                dateCreated: x['date_created'],
                sid: x['sid'],
                dateUpdated: x['date_updated'],
                status: x['status'],
                channelMessageSid: x['channel_message_sid'],
                conversationSid: x['conversation_sid'],
                errorCode: x['error_code'],
                participantSid: x['participant_sid']),
            source: (pageToken, pageSize) =>
                _getDetailedDeliveryReceiptsPaginator(
                    pageToken: pageToken, pageSize: pageSize),
            prevToken: response.data['meta']['previous_token'],
            nextToken: response.data['meta']['next_token']));
  }
}

/**
 * Fired when the Message's properties or body has been updated.
 * @event Message#updated
 * @type {Object}
 * @property {Message} message - Updated Message
 * @property {Message#UpdateReason[]} updateReasons - List of Message's updated event reasons
 */
