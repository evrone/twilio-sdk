enum PushNotificationType {
  newMessage,
  addedToConversation,
  removedFromConversation,
  unknown
}

PushNotificationType notificationTypeFromString(String type) {
  switch (type) {
    case 'new_message':
      return PushNotificationType.newMessage;
    case 'added_to_conversation':
      return PushNotificationType.addedToConversation;
    case 'removed_from_conversation':
      return PushNotificationType.removedFromConversation;
    default:
      return PushNotificationType.unknown;
  }
}
