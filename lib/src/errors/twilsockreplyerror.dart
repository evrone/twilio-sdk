import 'package:twilio_conversations/src/services/websocket/models/messages/reply.dart';

import 'twilsockerror.dart';

class TwilsockReplyError extends TwilsockError {
  TwilsockReplyError(String description, this.reply) : super(description);

  final Reply reply;
}
