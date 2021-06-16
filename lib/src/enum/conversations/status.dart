enum ConversationStatus { notParticipating, joined, unknown }

ConversationStatus conversationStatusFromString(String status) {
  switch (status) {
    case 'notParticipating':
      return ConversationStatus.notParticipating;
    case 'joined':
      return ConversationStatus.joined;
  }
  return ConversationStatus.unknown;
}
