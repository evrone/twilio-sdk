import 'dart:async';

import 'package:iso_duration_parser/iso_duration_parser.dart';
import 'package:twilio_conversations/src/config/client_info.dart';
import 'package:twilio_conversations/src/services/sync/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_list/sync_list.dart';
import 'package:twilio_conversations/src/vendor/deffered/deffered.dart';
import 'package:uuid/uuid.dart';

import '../../config/conversations.dart';
import '../../const/responsecodes.dart';
import '../../debug.dart';
import '../../errors/sessionerror.dart';
import 'models/command.dart';
import 'models/context.dart';
import 'models/session_links.dart';

const SDK_VERSION = '1.2.0';
const SESSION_PURPOSE = 'com.twilio.rtd.ipmsg';

class Session {
  Session(SyncClient<Command> syncClient, ConversationsConfiguration config)
      : _syncClient = syncClient,
        _config = config {
    final info = ClientInfo();
    _endpointPlatform = [
      'Dart',
      SDK_VERSION,
      info.os,
      info.pl,
      info.plVer,
    ].join('|');
  }

  final SyncClient<Command> _syncClient;
  SyncClient<Command> get sessionClient => _syncClient;
  String _endpointPlatform;
  final ConversationsConfiguration _config;
  final Map<String, Command> _pendingCommands = {};
  Future<SyncList> _sessionStreamPromise;
  final Deferred<SessionContext> _sessionInfo = Deferred<SessionContext>();
  Deferred<SessionContext> get sessionInfo => _sessionInfo;
  SessionContext _currentContext = SessionContext();

  String get identity => sessionInfo.current.identity;
  bool get reachabilityEnabled => _currentContext.reachabilityEnabled;

  void _handleContextUpdate(SessionContext updatedContext) {
    Debug.log('Session context updated');
    Debug.log('new session context: $updatedContext');
    _currentContext = updatedContext;
    if (updatedContext.identity != null &&
        updatedContext.userInfo != null &&
        updatedContext.links != null &&
        updatedContext.myChannels != null &&
        updatedContext.channels != null) {
      return; // not enough data to proceed, wait
    }
    Debug.log('new session context accepted');
    _sessionInfo.set(updatedContext);
  }

  Future<SyncList> initialize() {
    final context = SessionContext(
        type: 'IpMsgSession',
        apiVersion: '4',
        endpointPlatform: _endpointPlatform);
    _sessionStreamPromise =
        _syncClient.list(context: context.toMap(), purpose: SESSION_PURPOSE);
    _sessionStreamPromise.then((list) {
      Debug.log('Session created ${list.sid}');

      list.on('itemAdded', (args) => _processCommandResponse(args['item']));
      list.on('itemUpdated', (args) => _processCommandResponse(args['item']));
      list.on(
          'contextUpdated', (args) => _handleContextUpdate(args['context']));

      return list;
    });

    return _sessionStreamPromise;
  }

  /// Sends the command to the server
  /// @returns Future the promise, which is being fulfilled only when service will reply
  Future<SyncList<Command>> addCommand(String action, params) async =>
      await _processCommand(action, params);

  Future<SyncList<Command>> _processCommand(String action, params,
      {createSessionIfNotFound = true}) async {
    final command = Command();
    command.request = params;
    command.request.action = action;
    command.commandId = Uuid().v4();
    Debug.log('Adding command: $action, ${command.commandId}');
    Debug.log('command arguments: $params, $createSessionIfNotFound');
    SyncList<Command> list;
    try {
      list = await _sessionStreamPromise;
      _pendingCommands[command.commandId] =
          Command(commandId: command.commandId, request: command.request);
      await list.push(command);

      Debug.log('Command accepted by server ${command.commandId}');
    } catch (err) {
      _pendingCommands.remove(command.commandId);
      Debug.log('Failed to add a command to the session' + err.toString());
      if ((err.code == ResponseCodes.ACCESS_FORBIDDEN_FOR_IDENTITY ||
              err.code == ResponseCodes.LIST_NOT_FOUND) &&
          createSessionIfNotFound) {
        Debug.log('recreating session...');
        await initialize();
        return _processCommand(action, params,
            createSessionIfNotFound: false); // second attempt
      } else {
        throw Exception('Can\'t add command: ' + err.message);
      }
    }
    return list;
  }

  void _processCommandResponse(Map<String, dynamic> entity) {
    if (entity['data']['response'] != null &&
        entity['data']['commandId'] != null &&
        _pendingCommands.containsKey(entity['data']['commandId'])) {
      final data = entity['data'];
      final commandId = data.commandId;
      if (data.response.status == ResponseCodes.HTTP_200_OK) {
        Debug.log('Command succeeded: $data');
        final resolve = _pendingCommands[commandId].resolve;
        _pendingCommands.remove(commandId);
        resolve(data.response);
      } else {
        Debug.log('Command failed: $data');
        final reject = _pendingCommands[commandId].reject;
        _pendingCommands.remove(commandId);
        throw ConversationsSessionError(
            data.response.statusText, data.response.status);
      }
    }
  }

  Future<SessionContext> _getSessionContext() async {
    return _sessionStreamPromise.then(
        (stream) async => SessionContext.fromMap(await stream.getContext()));
  }

  Future<SessionLinks> getSessionLinks() async {
    final info = await _sessionInfo.promise;
    return SessionLinks(
        publicChannelsUrl: _config.url + info.links.publicChannelsUrl,
        myChannelsUrl: _config.url + info.links.myChannelsUrl,
        typingUrl: _config.url + info.links.typingUrl,
        syncListUrl: _config.url + info.links.syncListUrl,
        usersUrl: _config.url + info.links.usersUrl,
        mediaServiceUrl: info.links.mediaServiceUrl,
        messagesReceiptsUrl: _config.url + info.links.messagesReceiptsUrl);
  }

  Future getConversationsId() async {
    final info = await _sessionInfo.promise;
    return info.channels;
  }

  Future getMyConversationsId() async {
    final info = await _sessionInfo.promise;
    return info.myChannels;
  }

  Future getMaxUserInfosToSubscribe() async {
    final info = await _sessionInfo.promise;
    return _config.userInfosToSubscribeOverride ??
        info.userInfosToSubscribe ??
        _config.userInfosToSubscribeDefault;
  }

  Future<Map<String, dynamic>> getUsersData() {
    return _sessionInfo.promise
        .then((info) => ({'user': info.userInfo, 'identity': info.identity}));
  }

  Future<double> getConsumptionReportInterval() async {
    final context = await _getSessionContext();
    final consumptionIntervalToUse =
        _config.consumptionReportIntervalOverride ??
            context.consumptionReportInterval ??
            _config.consumptionReportIntervalDefault;
    try {
      return IsoDuration.parse(consumptionIntervalToUse).toSeconds();
    } catch (e) {
      Debug.log(
          'Failed to parse consumption report interval $consumptionIntervalToUse using default value ${_config.consumptionReportIntervalDefault}');
      return IsoDuration.parse(_config.consumptionReportIntervalDefault)
          .toSeconds();
    }
  }

  Future<double> getHttpCacheInterval() async {
    final context = await _getSessionContext();
    final cacheIntervalToUse = _config.httpCacheIntervalOverride ??
        context.httpCacheInterval ??
        _config.httpCacheIntervalDefault;
    try {
      return IsoDuration.parse(cacheIntervalToUse).toSeconds();
    } catch (e) {
      Debug.log(
          'Failed to parse cache interval $cacheIntervalToUse using default value ${_config.httpCacheIntervalDefault}');
      return IsoDuration.parse(_config.httpCacheIntervalDefault).toSeconds();
    }
  }
}
