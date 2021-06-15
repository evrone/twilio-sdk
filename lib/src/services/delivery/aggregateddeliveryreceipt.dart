enum DeliveryAmount { none, some, all }

class AggregatedDeliveryDescriptor {
  AggregatedDeliveryDescriptor(
      {this.failed,
      this.read,
      this.delivered,
      this.sent,
      this.total,
      this.undelivered});
  final int total;
  final DeliveryAmount delivered;
  final DeliveryAmount failed;
  final DeliveryAmount read;
  final DeliveryAmount sent;
  final DeliveryAmount undelivered;
}

/// @classdesc Contains aggregated information about a {@link Message}'s delivery statuses across all {@link Participant}s
/// of a {@link Conversation}.
///
/// At any moment during delivering message to a {@link Participant} the message can have zero or more of following
/// delivery statuses:
///
/// <ul><li>
/// Message considered as <b>sent</b> to a participant, if the nearest upstream carrier accepted the message.
/// </li><li>
/// Message considered as <b>delivered</b> to a participant, if Twilio has received confirmation of message
/// delivery from the upstream carrier, and, where available, the destination handset.
/// </li><li>
/// Message considered as <b>undelivered</b> to a participant, if Twilio has received a delivery receipt
/// indicating that the message was not delivered. This can happen for many reasons including carrier content
/// filtering and the availability of the destination handset.
/// </li><li>
/// Message considered as <b>read</b> by a participant, if the message has been delivered and opened by the
/// recipient in the conversation. The recipient must have enabled read receipts.
/// </li><li>
/// Message considered as <b>failed</b> to be delivered to a participant if the message could not be sent.
/// This can happen for various reasons including queue overflows, account suspensions and media
/// errors (in the case of MMS for instance).
///</li></ul>
///
/// {@link AggregatedDeliveryReceipt} class contains aggregated value {@link AggregatedDeliveryReceipt#DeliveryAmount} for each delivery status.
///
/// @property {int} total - Maximum int of delivery events expected for the message
/// @property {AggregatedDeliveryReceipt#DeliveryAmount} sent - Amount of participants that have <b>sent</b> delivery status for the message.
/// @property {AggregatedDeliveryReceipt#DeliveryAmount} delivered - Amount of participants that have <b>delivered</b> delivery status
///   for the message.
/// @property {AggregatedDeliveryReceipt#DeliveryAmount} read - Amount of participants that have <b>read</b> delivery status for the message.
/// @property {AggregatedDeliveryReceipt#DeliveryAmount} undelivered - Amount of participants that have <b>undelivered</b> delivery status
///   for the message.
/// @property {AggregatedDeliveryReceipt#DeliveryAmount} failed - Amount of participants that have <b>failed</b> delivery status for the message.
class AggregatedDeliveryReceipt {
  /// Signifies amount of participants which have the status for the message.
  /// @typedef {('none'|'some'|'all')} AggregatedDeliveryReceipt#DeliveryAmount
  AggregatedDeliveryReceipt(AggregatedDeliveryDescriptor data) : state = data;

  AggregatedDeliveryDescriptor state;

  /// @return Maximum int of delivery events expected for the message.
  int get total {
    return state.total;
  }

  /// Message considered as <b>sent</b> to a participant, if the nearest upstream carrier accepted the message.
  ///
  /// @return {@link DeliveryAmount} of participants that have <b>sent</b> delivery status for the message.
  DeliveryAmount get sent {
    return state.sent;
  }

  /// Message considered as <b>delivered</b> to a participant, if Twilio has received confirmation of message
  /// delivery from the upstream carrier, and, where available, the destination handset.
  ///
  /// @return {@link DeliveryAmount} of participants that have <b>delivered</b> delivery status for the message.
  DeliveryAmount get delivered {
    return state.delivered;
  }

  /// Message considered as <b>read</b> by a participant, if the message has been delivered and opened by the
  /// recipient in the conversation. The recipient must have enabled read receipts.
  ///
  /// @return {@link DeliveryAmount} of participants that have <b>read</b> delivery status for the message.
  DeliveryAmount get read {
    return state.read;
  }

  /// Message considered as <b>undelivered</b> to a participant, if Twilio has received a delivery receipt
  /// indicating that the message was not delivered. This can happen for many reasons including carrier content
  /// filtering and the availability of the destination handset.
  ///
  /// @return {@link DeliveryAmount} of participants that have <b>undelivered</b> delivery status for the message.
  DeliveryAmount get undelivered {
    return state.undelivered;
  }

  /// Message considered as <b>failed</b> to be delivered to a participant if the message could not be sent.
  /// This can happen for various reasons including queue overflows, account suspensions and media
  /// errors (in the case of MMS for instance). Twilio does not charge you for failed messages.
  ///
  /// @return {@link DeliveryAmount} of participants that have <b>failed</b> delivery status for the message.
  DeliveryAmount get failed {
    return state.failed;
  }

  void update(data) {
    state = data;
  }

  bool isEquals(data) {
    final isTotalSame = total == data.total;
    final isSentSame = sent == data.sent;
    final isDeliveredSame = delivered == data.delivered;
    final isReadSame = read == data.read;
    final isUndeliveredSame = undelivered == data.undelivered;
    final isFailedSame = failed == data.failed;
    return isTotalSame &&
        isSentSame &&
        isDeliveredSame &&
        isReadSame &&
        isUndeliveredSame &&
        isFailedSame;
  }
}
