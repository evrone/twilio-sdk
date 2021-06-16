import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/core/network.dart';
import 'package:twilio_conversations/src/enum/sync/open_mode.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/models/conversation.dart';
import 'package:twilio_conversations/src/models/message.dart';
import 'package:twilio_conversations/src/services/router/client.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_list/sync_list.dart';
import 'package:twilio_conversations/src/utils/sync_paginator.dart';

import '../core/session/session.dart';

/// Represents the collection of messages in a conversation
class Messages extends Stendo {
  Messages(
      {this.conversation,
      this.session,
      this.mcsClient,
      this.network,
      this.syncClient})
      : super();

  Session session;
  McsClient mcsClient;
  ConversationNetwork network;
  SyncClient syncClient;
  final Conversation conversation;
  Map<int, Message> messagesByIndex = {};
  Future<SyncList> messagesListPromise;

  /// Subscribe to the Messages Event Stream
  /// @param [String] name - The name of Sync object for the Messages resource.
  /// @returns [Future]
  Future<SyncList> subscribe(String name) {
    return messagesListPromise = messagesListPromise ??
        syncClient.list(id: name, mode: OpenMode.openExisting).then((list) {
          list.on('itemAdded', (args) {
            // debug(conversation.sid + ' itemAdded: ' + args.item.index);
            final message = Message(
                conversation: conversation,
                session: session,
                mcsClient: mcsClient,
                network: network,
                index: args['item'].index,
                data: args['item'].data);
            if (messagesByIndex.containsKey(message.index)) {
              // debug('Message arrived, but already known and ignored', conversation.sid, message.index);
              return;
            }
            messagesByIndex[message.index] = message;
            message.on(
                'updated', (args) => emit('messageUpdated', payload: args));
            emit('messageAdded', payload: message);
          });
          list.on('itemRemoved', (args) {
            // debug(conversation.sid + ' itemRemoved: ' + args.index);
            final index = args['index'];
            if (messagesByIndex.containsKey(index)) {
              final message = messagesByIndex[index];
              messagesByIndex.remove(message.index);
              message.removeListenersFrom('updated'); // todo
              emit('messageRemoved', payload: message);
            }
          });
          list.on('itemUpdated', (args) {
            // debug(conversation.sid + ' itemUpdated: ' + args.item.index);
            final message = messagesByIndex[args['item'].index];
            if (message != null) {
              message.update(args.item.data);
            }
          });
          return list;
        }).onError((error, stackTrace) {
          messagesListPromise = null;
          if (syncClient.connectionState != TwilsockState.disconnected) {
            // error('Failed to get messages object for conversation', conversation.sid, err);
          }
          // debug('ERROR: Failed to get messages object for conversation', conversation.sid, err);
          throw error;
        });
  }

  Future unsubscribe() async {
    if (messagesListPromise != null) {
      final entity = await messagesListPromise;
      entity.close();
      messagesListPromise = null;
    }
  }

  /// Send Message to the conversation
  /// @param [String] message - Message to post
  /// @param {any} attributes Message attributes
  /// @param {Conversation.SendEmailOptions} emailOptions Options that modify E-mail integration behaviors.
  /// @returns Returns promise which can fail
  Future send(String message,
      {Map<String, dynamic> attributes = const <String, dynamic>{},
      String subject}) {
    // debug('Sending text message', message, attributes, emailOptions);
    return session.addCommand('sendMessage', {
      'channelSid': conversation.sid,
      'text': message,
      attributes: json.encode(attributes),
      subject: subject,
    });
  }

  /// Send Media Message to the conversation
  /// @param {FormData | Conversation#SendMediaOptions} mediaContent - Media content to post
  /// @param {any} attributes Message attributes
  /// @returns Returns promise which can fail
  Future sendMedia(dynamic mediaContent,
      {Map<String, dynamic> attributes = const <String, dynamic>{},
      String subject}) async {
    // debug('Sending media message', mediaContent, attributes, emailOptions);
    var media;
    if (mediaContent is FormData) {
      // debug('Sending media message as FormData', mediaContent, attributes);
      media = await mcsClient.postFormData(mediaContent);
    } else {
      // debug('Sending media message as SendMediaOptions', mediaContent, attributes);
      final mediaOptions = mediaContent;
      if (mediaOptions.contentType == null || mediaOptions.media == null) {
        throw Exception(
            'Media content <Conversation#SendMediaOptions> must contain non-empty contentType and media');
      }
      media =
          await mcsClient.post(mediaOptions.contentType, mediaOptions.media);
    }
    // emailOptions are currently ignored for media messages.
    return session.addCommand('sendMediaMessage', {
      'channelSid': conversation.sid,
      'mediaSid': media.sid,
      attributes: json.encode(attributes)
    });
  }

  /// Returns messages from conversation using paginator interface
  /// @param [int] [pageSize] Number of messages to return in single chunk. By default it's 30.
  /// @param [String] [anchor] Most early message id which is already known, or 'end' by default
  /// @param [String] [direction] Pagination order 'backwards' or 'forward', or 'forward' by default
  /// @returns {Future<Paginator<Message>>} last page of messages by default
  Future<SyncPaginator<Message>> getMessages(int pageSize,
      {String anchor = 'end', String direction = 'backwards'}) {
    return _getMessages(
        pageSize: pageSize, anchor: anchor, direction: direction);
  }

  SyncPaginator<Message> wrapPaginator(String order, SyncPaginator page,
      List<Message> Function(List<Message>) op) {
    // We should swap next and prev page here, because of misfit of Sync and Chat paging conceptions
    final shouldReverse = order == 'desc';
    final np = () => page.nextPage().then((x) => wrapPaginator(order, x, op));
    final pp = () => page.prevPage().then((x) => wrapPaginator(order, x, op));

    final items = op(page.items)..sort((x, y) => x.index - y.index);

    return SyncPaginator<Message>(items,
        hasPrvPageOverride: shouldReverse ? page.hasNextPage : page.hasPrevPage,
        hasNxtPageOverride: shouldReverse ? page.hasPrevPage : page.hasNextPage,
        prevPageOverride: shouldReverse ? np : pp,
        nextPageOverride: shouldReverse ? pp : np);
  }

  Message _upsertMessage(int index, MessageState state) {
    final cachedMessage = messagesByIndex[index];
    if (cachedMessage != null) {
      return cachedMessage;
    }
    final message = Message(
        conversation: conversation,
        session: session,
        mcsClient: mcsClient,
        network: network,
        index: index,
        prevState: state);
    messagesByIndex[message.index] = message;
    message.on('updated', (args) => emit('messageUpdated', payload: args));
    return message;
  }

  /// Returns last messages from conversation
  /// @param [int] [pageSize] Number of messages to return in single chunk. By default it's 30.
  /// @param [String] [anchor] Most early message id which is already known, or 'end' by default
  /// @param [String] [direction] Pagination order 'backwards' or 'forward', or 'forward' by default
  /// @returns {Future<SyncPaginator<Message>>} last page of messages by default
  /// @private
  Future<SyncPaginator<Message>> _getMessages(
      {int pageSize = 30, anchor = 'end', direction = 'backwards'}) {
    final order = direction == 'backwards' ? 'desc' : 'asc';
    return messagesListPromise.then((messagesList) {
      messagesList.getItems(
          from: anchor != 'end' ? anchor : null,
          pageSize: pageSize,
          order: order);
    }).then((page) => wrapPaginator(
        order,
        page,
        (items) =>
            items.map((item) => _upsertMessage(item.index, item.state))));
  }
}
