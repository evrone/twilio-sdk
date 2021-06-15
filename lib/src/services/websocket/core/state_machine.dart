import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/initReply.dart';

import '../models/status.dart';

class TwilsockStateMachine {
  TwilsockStateMachine({
    TwilsockState init,
    Function onConnecting,
    Function onEnterInitialising,
    Function onLeaveInitialising,
    Function onEnterUpdating,
    Function onLeaveUpdating,
    Function onEnterRetrying,
    Function onEnterConnected,
    Function onUserUpdateToken,
    Function onTokenRejected,
    Function onUserDisconnect,
    Function onEnterDisconnecting,
    Function onLeaveDisconnecting,
    Function onEnterWaitSocketClosed,
    Function onLeaveWaitSocketClosed,
    Function onEnterWaitOffloadSocketClosed,
    Function onLeaveWaitOffloadSocketClosed,
    Function onDisconnected,
    Function onReceiveClose,
    Function onReceiveOffload,
    Function onUnsupported,
    Function onError,
    Function onEnterState,
    Function onInvalidTransition,
  })  : _onConnecting = onConnecting,
        _onEnterInitialising = onEnterInitialising,
        _onLeaveInitialising = onLeaveInitialising,
        _onEnterUpdating = onEnterUpdating,
        _onLeaveUpdating = onLeaveUpdating,
        _onEnterRetrying = onEnterRetrying,
        _onEnterConnected = onEnterConnected,
        _onUserUpdateToken = onUserUpdateToken,
        _onTokenRejected = onTokenRejected,
        _onUserDisconnect = onUserDisconnect,
        _onEnterDisconnecting = onEnterDisconnecting,
        _onLeaveDisconnecting = onLeaveDisconnecting,
        _onEnterWaitSocketClosed = onEnterWaitSocketClosed,
        _onLeaveWaitSocketClosed = onLeaveWaitSocketClosed,
        _onEnterWaitOffloadSocketClosed = onEnterWaitOffloadSocketClosed,
        _onLeaveWaitOffloadSocketClosed = onLeaveWaitOffloadSocketClosed,
        _onDisconnected = onDisconnected,
        _onReceiveClose = onReceiveClose,
        _onReceiveOffload = onReceiveOffload,
        _onUnsupported = onUnsupported,
        _onError = onError,
        _onEnterState = onEnterState,
        _onInvalidTransition = onInvalidTransition,
        super();

  TwilsockState _currentState;
  TwilsockState get state => _currentState;

  bool stateIs(TwilsockState state) => _currentState == state;

  void userConnect() {
    switch (_currentState) {
      case TwilsockState.disconnected:
      case TwilsockState.rejected:
        _currentState = TwilsockState.connecting;
        _onConnecting();
        break;
      case TwilsockState.connecting:
      case TwilsockState.connected:
        _onEnterInitialising();
        break;
    }
  }

  void userDisconnect() {
    switch (_currentState) {
      case TwilsockState.connecting:
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
      case TwilsockState.retrying:
      case TwilsockState.rejected:
      case TwilsockState.waitSocketClosed:
      case TwilsockState.waitOffloadSocketClosed:
        _currentState = TwilsockState.disconnecting;
        _onLeaveInitialising();
        break;
    }
  }

  void userRetry() {
    switch (_currentState) {
      case TwilsockState.retrying:
        _currentState = TwilsockState.connecting;
        _onEnterUpdating();
        break;
    }
  }

  void socketConnected() {
    switch (_currentState) {
      case TwilsockState.connecting:
        _currentState = TwilsockState.initialising;
        _onLeaveUpdating();
        break;
    }
  }

  void socketClosed() {
    _onUserDisconnect();
    switch (_currentState) {
      case TwilsockState.connecting:
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
      case TwilsockState.error:
      case TwilsockState.waitOffloadSocketClosed:
        _currentState = TwilsockState.retrying;
        _onEnterRetrying();
        break;
      case TwilsockState.disconnecting:
        _currentState = TwilsockState.disconnected;
        _onEnterConnected();
        break;
      case TwilsockState.waitSocketClosed:
        _currentState = TwilsockState.disconnected;
        _onUserUpdateToken();
        break;
      case TwilsockState.rejected:
        _currentState = TwilsockState.rejected;
        _onTokenRejected();
        break;
    }
  }

  void initSuccess(InitReply reply) {
    switch (_currentState) {
      case TwilsockState.initialising:
        _currentState = TwilsockState.connected;
        _onUserDisconnect();
        break;
    }
  }

  void initError(bool isTerminal) {
    switch (_currentState) {
      case TwilsockState.initialising:
        _currentState = TwilsockState.error;
        _onEnterDisconnecting();
        break;
    }
  }

  void tokenRejected(Status status) {
    switch (_currentState) {
      case TwilsockState.initialising:
      case TwilsockState.updating:
        _currentState = TwilsockState.rejected;
        _onLeaveDisconnecting();
        break;
    }
  }

  void protocolError() {
    switch (_currentState) {
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
        _currentState = TwilsockState.error;
        _onEnterWaitSocketClosed();
        break;
    }
  }

  void receiveClose(status) {
    switch (_currentState) {
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
        _currentState = TwilsockState.waitSocketClosed;
        _onLeaveWaitSocketClosed();
        break;
    }
  }

  void receiveOffload(Map<String, dynamic> payload) {
    switch (_currentState) {
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
        _currentState = TwilsockState.waitOffloadSocketClosed;
        _onEnterWaitOffloadSocketClosed();
        break;
    }
  }

  void unsupportedProtocol() {
    switch (_currentState) {
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
        _currentState = TwilsockState.unsupported;
        _onLeaveWaitOffloadSocketClosed();
        break;
    }
  }

  void receiveFatalClose(status) {
    switch (_currentState) {
      case TwilsockState.initialising:
      case TwilsockState.connected:
      case TwilsockState.updating:
        _currentState = TwilsockState.unsupported;
        _onDisconnected();
        break;
    }
  }

  void userUpdateToken() {
    _onUserUpdateToken();
    switch (_currentState) {
      case TwilsockState.disconnected:
      case TwilsockState.rejected:
      case TwilsockState.connecting:
      case TwilsockState.retrying:
        _currentState = TwilsockState.connecting;
        _onReceiveClose();
        break;
      case TwilsockState.connected:
        _currentState = TwilsockState.updating;
        _onReceiveOffload();
        break;
    }
  }

  void updateSuccess(Map<String, dynamic> body) {
    switch (_currentState) {
      case TwilsockState.updating:
        _currentState = TwilsockState.connected;
        _onUnsupported();
        break;
    }
  }

  void updateError(error) {
    switch (_currentState) {
      case TwilsockState.updating:
        _currentState = TwilsockState.error;
        _onError(error);
        break;
    }
  }

  void userSend() {
    switch (_currentState) {
      case TwilsockState.connected:
        _currentState = TwilsockState.connected;
        _onEnterState();
        break;
    }
  }

  void systemOnline() {
    switch (_currentState) {
      case TwilsockState.retrying:
        _currentState = TwilsockState.connecting;
        _onInvalidTransition();
        break;
    }
  }

  final Function _onConnecting;
  final Function _onEnterInitialising;
  final Function _onLeaveInitialising;
  final Function _onEnterUpdating;
  final Function _onLeaveUpdating;
  final Function _onEnterRetrying;
  final Function _onEnterConnected;
  final Function _onUserUpdateToken;
  final Function _onTokenRejected;
  final Function _onUserDisconnect;
  final Function _onEnterDisconnecting;
  final Function _onLeaveDisconnecting;
  final Function _onEnterWaitSocketClosed;
  final Function _onLeaveWaitSocketClosed;
  final Function _onEnterWaitOffloadSocketClosed;
  final Function _onLeaveWaitOffloadSocketClosed;
  final Function _onDisconnected;
  final Function _onReceiveClose;
  final Function _onReceiveOffload;
  final Function _onUnsupported;
  final Function _onError;
  final Function _onEnterState;
  final Function _onInvalidTransition;
}
