import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';

import 'abstract_message.dart';

class Update extends AbstractMessage {
  final ChannelMessageType method = ChannelMessageType.update;
  String token;
  Update(this.token);
}
