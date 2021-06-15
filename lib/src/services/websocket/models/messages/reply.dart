import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';

import '../status.dart';
import 'abstract_message.dart';

class Reply extends AbstractMessage {
  Reply({String id, this.status, this.method, this.body, this.header})
      : super(id: id);
  ChannelMessageType method = ChannelMessageType.reply;
  String payloadType = 'application/json';
  Status status = Status(code: 200, status: 'OK');
  var header;
  var body;
}
