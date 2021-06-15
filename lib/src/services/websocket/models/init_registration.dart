class InitRegistration {
  InitRegistration(
      {this.type,
      this.messageTypes,
      this.notificationProtocolVersion,
      this.product});
  String product;
  String type;
  int notificationProtocolVersion;
  List<String> messageTypes;
}
