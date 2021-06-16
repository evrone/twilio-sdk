import 'package:twilio_conversations/src/enum/conversations/push_notification_type.dart';

/// @classdesc Push notification representation within Conversations Client
/// @property String [action] - Notification action ('click_action' in FCM/GCM terms and 'category' in APN terms)
/// @property int [badge] - Number for the badge
/// @property String body - Notification text
/// @property {PushNotification#ConversationData} data - Additional Conversation data
/// @property String [sound] - Notification sound
/// @property String [title] - Notification title
/// @property [PushNotificationType] type - Notification type
class PushNotification {
  String title;
  String body;
  String sound;
  int badge;
  String action;
  PushNotificationType type;
  Map<String, dynamic> data;
  /**
   * Conversation push notification type
   * @typedef {('twilio.conversations.new_message' | 'twilio.conversations.added_to_conversation'
      | 'twilio.conversations.removed_from_conversation')} PushNotification#NotificationType
   */
  /**
   * Additional Conversations data for given Push Notification
   * @typedef {Object} PushNotification#ConversationData
   * @property String [conversationSid] - SID of Conversation
   * @property int [messageIndex] - Index of Message in Conversation
   * @property String [messageSid] - SID of Message
   */
  /// @param {PushNotification.Descriptor} data - initial data for PushNotification
  PushNotification(
      {this.type,
      this.data,
      this.body,
      this.action,
      this.title,
      this.badge,
      this.sound});
}
