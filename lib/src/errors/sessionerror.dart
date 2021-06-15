class ConversationsSessionError extends Error {
  ConversationsSessionError(this.message, this.code) : super();

  static const String name = 'SessionError';
  String message;
  String code;
}
