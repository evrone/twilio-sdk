import 'package:twilio_conversations/src/enum/conversations/detailed_delivery_status.dart';

/// @classdesc Represents a delivery receipt of a {@link Message}.
///
/// @property {String} sid - The unique identifier for Delivery Receipt
/// @property {String} messageSid - The unique identifier for Conversation Message
/// @property {String} conversationSid - The unique identifier for Conversation
/// @property {String} channelMessageSid - The unique identifier for the ‘channel’ message e.g WAxx for Whatsapp, SMxx for SMS
/// @property {String} participantSid - Participant's unique identifier
/// @property {DetailedDeliveryReceipt#Status} status - Message delivery status
/// @property {int | null} errorCode - Numeric error code mapped from Status callback code. Information about the error codes can be found
/// <a href='https://www.twilio.com/docs/sms/api/message-resource#delivery-related-errors'>here</a>.
/// @property {String} dateCreated - When Delivery Receipt was created
/// @property {String} dateUpdated - When Delivery Receipt was updated
class DetailedDeliveryReceipt {
  String sid;
  String messageSid;
  String conversationSid;
  String channelMessageSid;
  String participantSid;
  DetailedDeliveryStatus status;
  int errorCode;
  String dateCreated;
  String dateUpdated;

  /// Signifies the message delivery status.
  /// @typedef {('sent'|'delivered'|'failed'|'read'|'undelivered'|'queued')} DetailedDeliveryReceipt#Status
  DetailedDeliveryReceipt(
      {this.messageSid,
      this.dateCreated,
      this.sid,
      this.dateUpdated,
      this.status = DetailedDeliveryStatus.queued,
      this.channelMessageSid,
      this.conversationSid,
      this.errorCode = 0,
      this.participantSid});
}
