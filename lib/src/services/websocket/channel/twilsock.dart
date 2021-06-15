import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/abstract_message.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/reply.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/update.dart';

import '../../../config/twilsock.dart';
import '../../../errors/twilsockreplyerror.dart';
import '../cache/tocken_storage.dart';
import '../core/packet_interface.dart';
import '../core/state_machine.dart';
import '../util/backoff_retrier.dart';
import '../util/parser.dart';
import 'websocket_channel.dart';

const DISCONNECTING_TIMEOUT = 3000;
// Wraps asynchronous rescheduling
// Just makes it simpler to find these hacks over the code
void trampoline(VoidCallback f) {
  Future.delayed(Duration.zero, f);
}

/// Makes sure that body is properly Stringified
String preparePayload(payload) {
  if (payload is Map<String, dynamic>) {
    return json.encoder.convert(payload);
  } else if (payload is String) {
    return payload;
  }
  return null;
}

// class Request {
// }
// class Response {
// }
/// Twilsock channel level protocol implementation
class TwilsockChannel extends Stendo {
  TwilsockChannel(this.websocket, this.transport, this.config)
      : retrier = BackoffRetrier(config: config.retryPolicy),
        super() {
    websocket.on('connected', (_) => fsm.socketConnected());
    websocket.on('disconnected', (e) => fsm.socketClosed());
    websocket.on('message', (message) => onIncomingMessage(message));
    websocket.on(
        'socketError',
        (e) => emit('connectionError', payload: {
              'terminal': false,
              'message': 'Socket error: ${e.message}',
              'httpStatusCode': null,
              'errorCode': null
            }));

    retrier.on('attempt', (_) => retry());
    retrier.on('failed', (err) {
      //_1.log.warn('Retrying failed: ${err.message}');
      disconnect();
    });

    TokenStorage.window.addEventListener('online', (e) {
      //_1.log.debug('Browser reported connectivity state: online');
      resetBackoff();
      fsm.systemOnline();
    });
    TokenStorage.window.addEventListener('offline', (e) {
      //_1.log.debug('Browser reported connectivity state: offline');
      websocket.close();
      fsm.socketClosed();
    });

    fsm = TwilsockStateMachine(onConnecting: () {
      setupSocket();
      emit('connecting');
    }, onEnterInitialising: () {
      sendInit();
    }, onLeaveInitialising: () {
      cancelInit();
    }, onEnterUpdating: () {
      sendUpdate();
    }, onLeaveUpdating: () {
      cancelUpdate();
    }, onEnterRetrying: () {
      initRetry();
      emit('connecting');
    }, onEnterConnected: () {
      resetBackoff();
      onConnected();
    }, onUserUpdateToken: () {
      resetBackoff();
    }, onTokenRejected: () {
      resetBackoff();
      closeSocket(true);
      finalizeSocket();
    }, onUserDisconnect: () {
      closeSocket(true);
    }, onEnterDisconnecting: () {
      startDisconnectTimer();
    }, onLeaveDisconnecting: () {
      cancelDisconnectTimer();
    }, onEnterWaitSocketClosed: () {
      startDisconnectTimer();
    }, onLeaveWaitSocketClosed: () {
      cancelDisconnectTimer();
    }, onEnterWaitOffloadSocketClosed: () {
      startDisconnectTimer();
    }, onLeaveWaitOffloadSocketClosed: () {
      cancelDisconnectTimer();
    }, onDisconnected: () {
      resetBackoff();
      finalizeSocket();
    }, onReceiveClose: (event, args) {
      onCloseReceived(args);
    }, onReceiveOffload: (event, args) {
      //_1.log.debug('onreceiveoffload', args);
      modifyBackoff(args.body);
      onCloseReceived(args.status);
    }, onUnsupported: () {
      closeSocket(true);
      finalizeSocket();
    }, onError: (lifecycle, graceful) {
      closeSocket(graceful);
      finalizeSocket();
    }, onEnterState: (event) {
      if (event.from != 'none') {
        changeState(event);
      }
    }, onInvalidTransition: ({transition, from, to}) {
      //_1.log.warn('FSM: unexpected transition', from, to);
    });

    //
    // init: 'disconnected',
    // transitions: [

    // ],
  }

  WebSocketChannel websocket;
  PacketInterface transport;
  TwilsockConfiguration config;
  BackoffRetrier retrier;
  final terminalStates = [TwilsockState.disconnected, TwilsockState.rejected];
  TwilsockState lastEmittedState;
  final int tokenExpiredSasCode = 20104;
  String terminationReason = 'Connection is not initialized';
  Function disconnectedPromiseResolve;
  Timer disconnectingTimer;
  TwilsockStateMachine fsm = TwilsockStateMachine();
  void changeState(event) {
    //_1.log.debug('FSM: ${event.transition}: ${event.from} --> ${event.to}');
    if (lastEmittedState != state) {
      lastEmittedState = state;
      emit('stateChanged', payload: state);
    }
  }

  void resetBackoff() {
    //_1.log.trace('resetBackoff');
    retrier.stop();
  }

  void modifyBackoff(Map<String, dynamic> body) {
    //_1.log.trace('modifyBackoff', body);
    final backoffPolicy = body['backoff_policy'];
    if (backoffPolicy != null && backoffPolicy['reconnect_min_ms'] is int) {
      retrier.modifyBackoff(backoffPolicy['reconnect_min_ms']);
    }
  }

  void startDisconnectTimer() {
    //_1.log.trace('startDisconnectTimer');
    if (disconnectingTimer != null) {
      clearTimeout(disconnectingTimer);
      disconnectingTimer = null;
    }
    disconnectingTimer =
        Timer(Duration(milliseconds: DISCONNECTING_TIMEOUT), () {
      //_1.log.debug('disconnecting is timed out');
      closeSocket(true);
    });
  }

  void cancelDisconnectTimer() {
    //_1.log.trace('cancelDisconnectTimer');
    if (disconnectingTimer != null) {
      clearTimeout(disconnectingTimer);
      disconnectingTimer = null;
    }
  }

  bool get isConnected {
    return state == TwilsockState.connected && websocket.isConnected;
  }

  TwilsockState get state {
    switch (fsm.state) {
      case TwilsockState.connecting:
      case TwilsockState.initialising:
      case TwilsockState.retrying:
      case TwilsockState.error:
        return TwilsockState.connected;
      case TwilsockState.updating:
      case TwilsockState.connected:
        return TwilsockState.connected;
      case TwilsockState.rejected:
        return TwilsockState.rejected;
      case TwilsockState.disconnecting:
      case TwilsockState.waitSocketClosed:
      case TwilsockState.waitOffloadSocketClosed:
        return TwilsockState.disconnecting;
      case TwilsockState.disconnected:
      default:
        return TwilsockState.disconnected;
    }
  }

  void initRetry() {
    //_1.log.debug('initRetry');
    if (retrier.inProgress) {
      retrier.attemptFailed();
    } else {
      retrier.start();
    }
  }

  void retry() {
    if (fsm.state != TwilsockState.connecting) {
      //_1.log.trace('retry');
      websocket.close();
      fsm.userRetry();
    } else {
      //_1.log.trace('can\t retry as already connecting');
    }
  }

  void onConnected() {
    emit('connected');
  }

  void finalizeSocket() {
    //_1.log.trace('finalizeSocket');
    websocket.close();
    emit('disconnected');
    if (disconnectedPromiseResolve != null) {
      disconnectedPromiseResolve();
      disconnectedPromiseResolve = null;
    }
  }

  void setupSocket() {
    //_1.log.trace('setupSocket:', config.token);
    emit(
        'beforeConnect'); // This is used by client to record startup telemetry event
    websocket.connect();
  }

  void onIncomingMessage(ByteBuffer message) {
    final res = Parser.parse(message);
    if (res['method'] != 'reply') {
      confirmReceiving(res['header']);
    }
    if (res['method'] == 'notification') {
      emit('message', payload: {
        'message_type': res['header']['message_type'],
        'payload': res['payload']
      });
    } else if (res['header']['method'] == 'reply') {
      transport.processReply(Reply(
          id: res['header']['id'],
          status: res['header']['status'],
          header: res['header'],
          body: res['payload']));
    } else if (res['header']['method'] == 'client_update') {
      if (res['header']['client_update_type'] == 'token_about_to_expire') {
        emit('tokenAboutToExpire');
      }
    } else if (res['header']['method'] == 'close') {
      if (res['header']['status']['code'] == 308) {
        //_1.log.debug('Connection has been offloaded');
        fsm.receiveOffload(
            {'status': res['header']['status'], 'body': res['payload']});
      } else if (res['header']['status']['code'] == 406) {
        // Not acceptable message
        final message =
            'Server closed connection because can\'t parse protocol: ${json.encode(res['header']['status'])}';
        emitReplyConnectionError(message, res['header'], true);
        //_1.log.error(message);
        fsm.receiveFatalClose(message);
      } else if (res['header']['status']['code'] == 417) {
        // Protocol error
        //_1.log.error('Server closed connection because can't parse client reply: ${JSON.Stringify(res['header']['tatus)']');
        fsm.receiveFatalClose(res['header']['status']);
      } else if (res['header']['status']['code'] == 410) {
        // Expired token
        //_1.log.warn('Server closed connection: ${JSON.Stringify(res['header']['tatus)']');
        fsm.receiveClose(res['header']['status']);
        emit('tokenExpired');
      } else if (res['header']['status']['code'] == 401) {
        // Authentication fail
        //_1.log.error('Server closed connection: ${JSON.Stringify(res['header']['tatus)']');
        fsm.receiveClose(res['header']['status']);
      } else {
        //_1.log.warn('unexpected message: ', res['header']['tatus)']
        // Try to reconnect
        fsm.receiveOffload({'status': res['header']['status'], 'body': null});
      }
    }
  }

  Future sendInit() async {
    //_1.log.trace('sendInit');
    try {
      emit(
          'beforeSendInit'); // This is used by client to record startup telemetry event
      final reply = await transport.sendInit();
      config.updateContinuationToken = reply.continuationToken;
      config.confirmedCapabilities = reply.confirmedCapabilities;
      fsm.initSuccess(reply);
      emit('initialized', payload: reply);
      emit('tokenUpdated');
    } catch (ex) {
      if (ex is TwilsockReplyError) {
        var isTerminalError = false;
        //_1.log.warn('Init rejected by server: ${JSON.Stringify(ex.reply.status)}');
        emit(
            'sendInitFailed'); // This is used by client to record startup telemetry event
        // @todo emit telemetry from inside 'if' below for more granularity...
        if (ex.reply.status.code == 401 || ex.reply.status.code == 403) {
          isTerminalError = true;
          fsm.tokenRejected(ex.reply.status);
          if (ex.reply.status.code == tokenExpiredSasCode) {
            emit('tokenExpired');
          }
        } else if (ex.reply.status.code == 429) {
          modifyBackoff(ex.reply.body);
          fsm.initError(true);
        } else if (ex.reply.status.code == 500) {
          fsm.initError(false);
        } else {
          fsm.initError(true);
        }
        emitReplyConnectionError(ex.description, ex.reply, isTerminalError);
      } else {
        terminationReason = ex.message;
        emit('connectionError', payload: {
          'terminal': true,
          'message':
              'Unknown error during connection initialisation: ${ex.message}\n${json.encode(ex)}',
          'httpStatusCode': null,
          'errorCode': null
        });
        fsm.initError(true);
      }
      emit('tokenUpdated', payload: ex);
    }
  }

  Future<void> sendUpdate() async {
    //_1.log.trace('sendUpdate');
    final message = Update(config.token);
    try {
      final reply = await transport.sendWithReply(message);
      fsm.updateSuccess(reply.body);
      emit('tokenUpdated');
    } catch (ex) {
      if (ex is TwilsockReplyError) {
        var isTerminalError = false;
        //_1.log.warn('Token update rejected by server: ${JSON.Stringify(ex.reply.status)}');
        if (ex.reply.status.code == 401 || ex.reply.status.code == 403) {
          isTerminalError = true;
          fsm.tokenRejected(ex.reply.status);
          if (ex.reply.status.code == tokenExpiredSasCode) {
            emit('tokenExpired');
          }
        } else if (ex.reply.status.code == 429) {
          modifyBackoff(ex.reply.body);
          fsm.updateError(ex.reply.status);
        } else {
          fsm.updateError(ex.reply.status);
        }
        emitReplyConnectionError(ex.description, ex.reply, isTerminalError);
      } else {
        emit('error', payload: {
          'isTerminalError': false,
          'message': ex.description,
          'httpStatusCode': null,
          'errorCode': null
        });
        fsm.updateError(ex);
      }
      emit('tokenUpdated', payload: ex);
    }
  }

  void emitReplyConnectionError(String message, Reply header, bool terminal) {
    final description =
        header.status != null && header.status.description != null
            ? header.status.description
            : message;
    final httpStatusCode = header.status.code;
    final errorCode = header.status != null && header.status.code != null
        ? header.status.code
        : null;
    if (terminal != null) {
      terminationReason = description;
    }
    emit('connectionError', payload: {
      'terminal': terminal,
      'message': 'Connection error: $description',
      'httpStatusCode': httpStatusCode,
      'errorCode': errorCode
    });
  }

  void cancelInit() {
    //_1.log.trace('cancelInit');
    // TODO: implement
  }
  void cancelUpdate() {
    //_1.log.trace('cancelUpdate');
    // TODO: implement
  }

  /// Should be called for each message to confirm it received
  void confirmReceiving(AbstractMessage messageHeader) {
    //_1.log.trace('confirmReceiving');
    try {
      //@todo send telemetry events AnyEvents
      transport.send(Reply(id: messageHeader.id));
    } catch (e) {
      //_1.log.debug('failed to confirm packet receiving', e);
    }
  }

  /// Shutdown connection
  void closeSocket(bool graceful) {
    //_1.log.trace('closeSocket (graceful: ${graceful})');
    if (graceful && transport.isConnected) {
      transport.sendClose();
    }
    websocket.close();
    trampoline(() => fsm.socketClosed());
  }

  /// Initiate the twilsock connection
  /// If already connected, it does nothing
  void connect() {
    //_1.log.trace('connect');
    fsm.userConnect();
  }

  /// Close twilsock connection
  /// If already disconnected, it does nothing
  Future disconnect() {
    //_1.log.trace('disconnect');
    final completer = Completer();
    if (fsm.stateIs(TwilsockState.disconnected)) {
      completer.completeError('disconnected');
      return completer.future;
    }
    disconnectedPromiseResolve = completer.complete;
    fsm.userDisconnect();
    return completer.future;
  }

  /// Update fpa token for twilsock connection
  Future updateToken(String token) {
    final completer = Completer();
    //_1.log.trace('updateToken:', token);

    once('tokenUpdated', (e) {
      if (e) {
        completer.completeError(e);
      } else {
        completer.complete();
      }
    });
    fsm.userUpdateToken();
    return completer.future;
  }

  bool get isTerminalState {
    return terminalStates.contains(fsm.state);
  }

  String get getTerminationReason {
    return terminationReason;
  }

  void onCloseReceived(String reason) {
    websocket.close();
  }
}
