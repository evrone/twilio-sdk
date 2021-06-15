import 'package:twilio_conversations/src/enum/twilsock/method.dart';

import 'abstract_message.dart';

class NotificationContextUpdate extends AbstractMessage {
  NotificationContextUpdate({this.notificationCtxId, this.method});
  final Method method;
  final String notificationCtxId; // notification_ctx_id
}
