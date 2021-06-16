import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/config/notifications.dart';
import 'package:twilio_conversations/src/enum/notification/update_reason.dart';
import 'package:twilio_conversations/src/services/notifications/models/registration_state.dart';

List setDifference(a, b) {
  return [
    ...[...a].where((x) => !b.has(x)),
    ...[...b].where((x) => !a.has(x))
  ];
}

List hasDifference(a, b) {
  final reasons = <NotificationUpdateReason>{};
  if (a.notificationId != b.notificationId) {
    reasons.add(NotificationUpdateReason.notificationId);
  }
  if (a.token != b.token) {
    reasons.add(NotificationUpdateReason.token);
  }
  if (setDifference(a.messageTypes, b.messageTypes).isNotEmpty) {
    reasons.add(NotificationUpdateReason.messageType);
  }
  return [reasons.isNotEmpty, reasons];
}

class Connector extends Stendo {
  Connector(this.config) : super();

  final NotificationsConfiguration config;

  RegistrationState desiredState = RegistrationState();
  @override
  RegistrationState currentState = RegistrationState();
  bool hasActiveAttempt = false;

  Future<void> subscribe(String messageType) async {
    if (desiredState.messageTypes.contains(messageType)) {
      //_1.log.debug('message type already registered ', messageType);
      return;
    }
    desiredState.messageTypes.add(messageType);
    await persistRegistration();
  }

  Future<void> unsubscribe(String messageType) async {
    if (!desiredState.messageTypes.contains(messageType)) {
      return;
    }
    desiredState.messageTypes.remove(messageType);
    await persistRegistration();
  }

  void updateToken(String token) {
    desiredState.token = token;
    persistRegistration();
  }

  Future<void> persistRegistration() async {
    if (config.token == null || config.token.isEmpty) {
      //_1.log.trace('Can\'t persist registration: token is not set');
      return;
    }
    if (hasActiveAttempt) {
      //_1.log.trace('One registration attempt is already in progress');
      return;
    }
    final hasDif = hasDifference(desiredState, currentState);
    final bool needToUpdate = hasDif.first;
    final Set<NotificationUpdateReason> reasons = hasDif.last;
    if (!needToUpdate) {
      return;
    }
    if (currentState.notificationId == null) {
      reasons.remove(NotificationUpdateReason.notificationId);
    }
    //_1.log.trace('Persisting registration', reasons, desiredState);
    try {
      hasActiveAttempt = true;
      final stateToPersist = desiredState.clone();
      if (stateToPersist.messageTypes.isNotEmpty) {
        final persistedState =
            await updateRegistration(stateToPersist, reasons);
        currentState.token = persistedState.token;
        currentState.notificationId = persistedState.notificationId;
        currentState.messageTypes = persistedState.messageTypes;
        emit('stateChanged', payload: 'registered');
      } else {
        removeRegistration();
        currentState.token = stateToPersist.token;
        currentState.notificationId = stateToPersist.notificationId;
        currentState.messageTypes.clear();
        emit('stateChanged', payload: 'unregistered');
      }
    } finally {
      hasActiveAttempt = false;
      Future.delayed(Duration.zero, () => persistRegistration());
    }
  }

  set notificationId(String notificationId) {
    desiredState.notificationId = notificationId;
    persistRegistration();
  }

  // ignore: missing_return
  Future<RegistrationState> updateRegistration(
      RegistrationState registration, Set<NotificationUpdateReason> reasons) {}
  void removeRegistration() async {}
}
