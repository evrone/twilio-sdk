class RegistrationState {
  RegistrationState(
      {this.token = '', this.notificationId = '', this.messageTypes});

  String token;
  String notificationId;
  Set messageTypes = <String>{};

  RegistrationState clone() {
    return RegistrationState(
        token: token,
        notificationId: notificationId,
        messageTypes: messageTypes);
  }
}
