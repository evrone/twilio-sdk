class ReliableTransportState {
  ReliableTransportState(
      {this.transport = false,
      this.lastEmitted,
      this.overall = false,
      this.registration = false});
  bool overall;
  bool transport;
  bool registration;
  dynamic lastEmitted;
}
