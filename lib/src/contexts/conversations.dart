import 'dart:convert';

import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/core/network.dart';
import 'package:twilio_conversations/src/core/readhorizon.dart';
import 'package:twilio_conversations/src/core/session/session.dart';
import 'package:twilio_conversations/src/core/typingindicator.dart';
import 'package:twilio_conversations/src/enum/conversations/notification_level.dart';
import 'package:twilio_conversations/src/enum/conversations/status.dart';
import 'package:twilio_conversations/src/enum/sync/open_mode.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/services/router/client.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_list/sync_list.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_map/sync_map.dart';
import 'package:twilio_conversations/src/utils/sync_paginator.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';
import 'package:twilio_conversations/src/vendor/deffered/deffered.dart';

import '../models/conversation.dart';
import 'users.dart';

class Conversations extends Stendo {
  Conversations({
    Session session,
    SyncClient syncClient,
    SyncList syncList,
    Users users,
    TypingIndicator typingIndicator,
    ReadHorizon readHorizon,
    ConversationNetwork network,
    McsClient mcsClient,
  })  : _network = network,
        _session = session,
        _syncClient = syncClient,
        _syncList = syncList,
        _users = users,
        _mcsClient = mcsClient,
        _readHorizon = readHorizon,
        _typingIndicator = typingIndicator;

  final Session _session;
  final SyncClient _syncClient;
  final SyncList _syncList;
  final Users _users;
  final TypingIndicator _typingIndicator;
  final ReadHorizon _readHorizon;
  final ConversationNetwork _network;
  final McsClient _mcsClient;
  final Map<String, Conversation> _conversations = {};
  Map<String, Conversation> get conversations => _conversations;

  final Set _thumbstones = {};
  bool _syncListFetched = false;
  final Deferred<bool> syncListRead = Deferred<bool>();

  Future<SyncMap> get map => _session
      .getMyConversationsId()
      .then((name) => _syncClient.map(id: name, mode: OpenMode.openExisting));

  /// Add conversation to server
  /// @private
  /// @returns {Promise<Conversation>} Conversation
  Future<Conversation> addConversation(
      {Map<String, dynamic> attributes,
      String friendlyName,
      String uniqueName}) async {
    final response = await _session.addCommand('createConversation', {
      'friendlyName': friendlyName,
      'uniqueName': uniqueName,
      'attributes': json.encode(attributes)
    });
    final conversationSid = response.sid;
    final conversationDocument = response.uri; // todo
    final existingConversation = conversations[conversationSid];
    if (existingConversation != null) {
      await existingConversation.subscribe();
      return existingConversation;
    }
    final conversation = Conversation(
        ConversationServices(
            session: _session,
            users: _users,
            syncClient: _syncClient,
            mcsClient: _mcsClient,
            network: _network,
            typingIndicator: _typingIndicator,
            readHorizon: _readHorizon),
        ConversationDescriptor(
          channel: conversationDocument,
        ),
        conversationSid);
    conversations[conversation.sid] = conversation;
    _registerForEvents(conversation);
    await conversation.subscribe();
    emit('conversationAdded', payload: conversation);
    return conversation;
  }

  /// Fetch conversations list and instantiate all necessary objects
  Future<void> fetchConversations() async {
    await map
        .then((map) async {
          map.on('itemAdded', (args) {
            // debug('itemAdded: ' + args.item.key);
            _upsertConversation(DataSource.sync, args['item']['key'],
                ConversationDescriptor.fromMap(args['item']['data']));
          });
          map.on('itemRemoved', (args) {
            // debug('itemRemoved: ' + args.key);
            final sid = args.key;
            if (!_syncListFetched) {
              _thumbstones.add(sid);
            }
            final conversation = conversations[sid];
            if (conversation != null) {
              if (conversation != null &&
                  conversation.status ==
                      ConversationStatus
                          .joined /*|| conversation.status == 'invited'*/) {
                conversation.setStatus(
                    ConversationStatus.notParticipating, DataSource.sync);
                emit('conversationLeft', payload: conversation);
              }
              conversations.remove(sid);
              emit('conversationRemoved', payload: conversation);
              conversation.emit('removed', payload: conversation);
            }
          });
          map.on('itemUpdated', (args) {
            // debug('itemUpdated: ' + args.item.key);
            _upsertConversation(DataSource.sync, args['item']['key'],
                ConversationDescriptor.fromMap(args['item']['data']));
          });
          final upserts = [];
          var paginator = await _syncList.getPage();
          final items = paginator.items;
          items.forEach((item) {
            upserts.add(_upsertConversation(
                DataSource.synclist,
                item.channelSid,
                ConversationDescriptor(
                    status: conversationStatusFromString(item.status),
                    channel: item.channel,
                    notificationLevel:
                        notificationLevelFromString(item.notificationLevel),
                    lastConsumedMessageIndex: item.lastConsumedMessageIndex)));
          });
          while (paginator.hasNextPage) {
            paginator = await paginator.nextPage();
            paginator.items.forEach((item) {
              upserts.add(_upsertConversation(
                  DataSource.synclist,
                  item.channelSid,
                  ConversationDescriptor(
                      status: conversationStatusFromString(item.status),
                      channel: item.channel,
                      notificationLevel:
                          notificationLevelFromString(item.notificationLevel),
                      lastConsumedMessageIndex:
                          item.lastConsumedMessageIndex)));
            });
          }
          syncListRead.set(true);
          return Future.value(upserts);
        })
        .then((_) {
          _syncListFetched = true;
          _thumbstones.clear();
          // debug('Conversations list fetched');
        })
        .then((_) => this)
        .onError((e, trace) {
          if (_syncClient.connectionState == TwilsockState.disconnected) {
            // error('Failed to get conversations list', e);
          }
          // debug('ERROR: Failed to get conversations list', e);
          throw e;
        });
  }

  SyncPaginator _wrapPaginator(page, Function op) {
    return op(page.items).then((items) => {
          'items': items,
          'hasNextPage': page.hasNextPage,
          'hasPrevPage': page.hasPrevPage,
          'nextPage': () => page.nextPage().then((x) => _wrapPaginator(x, op)),
          'prevPage': () => page.prevPage().then((x) => _wrapPaginator(x, op))
        });
  }

  Future<SyncPaginator<Conversation>> getConversations(
      {String key, String from, int pageSize, String order}) {
    return map
        .then((conversationsMap) => conversationsMap.getItems(
            key: key, from: from, pageSize: pageSize, order: order))
        .then((page) async => _wrapPaginator(
            page,
            (items) => Future.value(items.map((item) =>
                _upsertConversation(DataSource.sync, item.key, item.data)))));
  }

  Future<Conversation> getConversation(String sid) {
    return map
        .then((conversationsMap) => conversationsMap.getItems(key: sid))
        .then((page) => page.items.map((item) =>
            _upsertConversation(DataSource.sync, item.key, item.data)))
        .then((items) => items.isNotEmpty ? items.first : null);
  }

  Future<Conversation> getConversationByUniqueName(String uniqueName) async {
    var _a, _b;
    final links = await _session.getSessionLinks();
    final url =
        UriBuilder(links.myChannelsUrl).addPathSegment(uniqueName).build();
    final response = await _network.get(url);
    final body = response.data;
    final sid = body['channel_sid'];
    final status = ((_a = body) == null || _a == null)
        ? ConversationStatus.unknown
        : _a.status;
    final notificationLevel =
        (_b = body) == null || _b == null ? null : _b.notification_level;
    final data = ConversationDescriptor(
      entityName: null,
      lastConsumedMessageIndex: body['lastConsumedMessageIndex'],
      status: status,
      friendlyName: body['friendly_name'],
      dateUpdated: body['date_updated'],
      dateCreated: body['date_created'],
      uniqueName: body['unique_name'],
      createdBy: body['created_by'],
      attributes: body['attributes'],
      channel: '$sid.channel',
      notificationLevel: notificationLevel,
    );
    return _upsertConversation(DataSource.sync, sid, data);
  }

  Future<Conversation> getWhisperConversation(String sid) async {
    var _a, _b, _c, _d;
    final links = await _session.getSessionLinks();
    final url = UriBuilder(links.publicChannelsUrl).addPathSegment(sid).build();
    final response = await _network.get(url);
    final body = response.data;
    if (body.type != 'private') {
      return null;
    }
    // todo: refactor this after the back-end change.
    // Currently, a conversation that is created using a non-conversations-specific
    // endpoint (i.e., a chat-specific endpoint) will not have a state property set.
    // The back-end team will fix this, but only when they get some more time to work
    // on this. For now, the SDK will assume that the default state is active when
    // the property is absent from the REST response. The back-end team also mentioned
    // that the state property will become a proper JSON object, as opposed to a JSON
    // string, which is also covered in the following code.
    var state;
    // If the state property is a string, it's expected to be a string that represents
    // a JSON object.
    if (body.state is String) {
      state = jsonDecode(body.state);
    }
    // If the state property is already a non-nullable object, then no JSON parsing is
    // required.
    if (body.state != null && body.state is Map) {
      state = body.state;
    }
    if (((_b = (_a = state) == null || _a == null ? null : _a['state.v1']) ==
                    null ||
                _b == null
            ? null
            : _b.current) ==
        'closed') {
      return null;
    }
    final status = ((_a = body) == null || _a == null)
        ? ConversationStatus.unknown
        : _a.status;
    final notificationLevel =
        (_b = body) == null || _b == null ? null : _b.notification_level;

    return _upsertConversation(
        DataSource.sync,
        sid,
        ConversationDescriptor(
          lastConsumedMessageIndex: body['lastConsumedMessageIndex'],
          status: conversationStatusFromString(status),
          friendlyName: body['friendly_name'],
          dateUpdated: body['date_updated'],
          dateCreated: body['date_created'],
          uniqueName: body['unique_name'],
          createdBy: body['created_by'],
          attributes: body['attributes'],
          channel: '$sid.channel',
          notificationLevel: notificationLevel,
        ));
  }

  Future<Conversation> _upsertConversation(
      DataSource source, String sid, ConversationDescriptor desc) async {
    // trace('upsertConversation(sid=' + sid + ', data=', data);
    var conversation = conversations[sid];
    // Update the Conversation's status if we know about it
    if (conversation != null) {
      // trace('upsertConversation: conversation ' + sid + ' is known and it\'s' +
      // ' status is known from source ' + conversation.statusSource() +
      //     ' and update came from source ' + source, conversation);
      if (conversation.statusSource == null ||
          source == conversation.statusSource ||
          (source == DataSource.synclist &&
              conversation.statusSource != DataSource.sync) ||
          source == DataSource.sync) {
        if (conversation.status != ConversationStatus.joined) {
          conversation.setStatus(ConversationStatus.joined, source);
          final updateData = {};
          if (desc.notificationLevel != null) {
            updateData['notificationLevel'] = desc.notificationLevel;
          }
          if (desc.lastConsumedMessageIndex != null) {
            updateData['lastConsumedMessageIndex'] =
                desc.lastConsumedMessageIndex;
          }
          if (updateData.isNotEmpty) {
            conversation.update(updateData);
          }
          await conversation.subscribe().then((_) {
            emit('conversationJoined', payload: conversation);
          });
        } else if (desc.status == ConversationStatus.notParticipating &&
            conversation.status == ConversationStatus.joined) {
          conversation.setStatus(ConversationStatus.notParticipating, source);
          conversation.update(desc.toMap());
          await conversation.subscribe().then((_) {
            emit('conversationLeft', payload: conversation);
          });
        } else if (desc.status == ConversationStatus.notParticipating) {
          await conversation.subscribe();
        } else {
          conversation.update(desc.toMap());
        }
      } else {
        // // trace('upsertConversation: conversation is known from sync and came from chat, ignoring', {
        // sid: sid,
        // data: desc.status,
        // conversation: conversation.status
        // });
      }
      return conversation.subscribe().then((_) => conversation);
    }
    if ((source == DataSource.chat || source == DataSource.synclist) &&
        _thumbstones.contains(sid)) {
      // if conversation was deleted, we ignore it
      // trace('upsertConversation: conversation is deleted and came again from chat, ignoring', sid);
      return null;
    }
    // Fetch the Conversation if we don't know about it
    // trace('upsertConversation: creating local conversation object with sid ' + sid, data);
    conversation = Conversation(
        ConversationServices(
            session: _session,
            users: _users,
            syncClient: _syncClient,
            mcsClient: _mcsClient,
            network: _network,
            typingIndicator: _typingIndicator,
            readHorizon: _readHorizon),
        desc,
        sid);
    conversations[sid] = conversation;
    return conversation.subscribe().then((_) {
      _registerForEvents(conversation);
      emit('conversationAdded', payload: conversation);
      if (desc.status == ConversationStatus.joined) {
        conversation.setStatus(ConversationStatus.joined, source);
        emit('conversationJoined', payload: conversation);
      }
      return conversation;
    });
  }

  void _onConversationRemoved(String sid) {
    final conversation = _conversations[sid];

    if (conversation != null) {
      _conversations.remove(sid);
      emit('conversationRemoved', payload: conversation);
    }
  }

  void _registerForEvents(Conversation conversation) {
    conversation.on('removed', (_) => _onConversationRemoved(conversation.sid));
    conversation.on(
        'updated', (args) => emit('conversationUpdated', payload: args));
    conversation.on('participantJoined', (_) => emit('participantJoined'));
    conversation.on('participantLeft', (_) => emit('participantLeft'));
    conversation.on('participantUpdated',
        (args) => emit('participantUpdated', payload: args));
    conversation.on('messageAdded', (_) => emit('messageAdded'));
    conversation.on(
        'messageUpdated', (args) => emit('messageUpdated', payload: args));
    conversation.on('messageRemoved', (_) => emit('messageRemoved'));
    conversation.on('typingStarted', (_) => emit('typingStarted'));
    conversation.on('typingEnded', (_) => emit('typingEnded'));
  }
}

enum DataSource {
  sync,
  chat,
  synclist,
}
