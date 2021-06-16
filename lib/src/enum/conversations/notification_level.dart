enum ConversationNotificationLevel {
  /// regular == default
  regular,

  muted
}

ConversationNotificationLevel notificationLevelFromString(String level) {
  switch (level) {
    case 'regular':
      return ConversationNotificationLevel.regular;
    case 'muted':
      return ConversationNotificationLevel.muted;
  }
  return ConversationNotificationLevel.regular;
}
