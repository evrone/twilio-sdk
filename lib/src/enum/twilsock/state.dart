enum TwilsockState {
  unknown,
  updating,
  initialising,
  disconnecting,
  disconnected,
  connecting,
  connected,
  unsupported,
  error,
  rejected,

  /// denied == rejected
  denied,
  retrying,
  waitSocketClosed,
  waitOffloadSocketClosed
}
