import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';

import 'abstract_message.dart';

class Close extends AbstractMessage {
  ChannelMessageType method = ChannelMessageType.close;
  Close() : super();
}
