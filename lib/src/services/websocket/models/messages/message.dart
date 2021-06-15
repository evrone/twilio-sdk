import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';

import '../protocol.dart';
import 'abstract_message.dart';

class Message extends AbstractMessage {
  Message(this.activeGrant, this.payloadType, this.httpRequest);
  final ChannelMessageType method = ChannelMessageType.message;
  final String activeGrant;
  final String payloadType;
  final Request httpRequest;
}
