import 'package:twilio_conversations/src/config/notifications.dart';
import 'package:twilio_conversations/src/enum/notification/channel_type.dart';
import 'package:twilio_conversations/src/enum/notification/update_reason.dart';
import 'package:twilio_conversations/src/services/notifications/models/registration_state.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/retrier.dart';

import 'connector.dart';

/// Manages the registrations on ERS service.
/// Deduplicates registrations and manages them automatically
class RegistrarConnector extends Connector {
  /// Creates new instance of the ERS registrar

  /// @param Object configuration
  /// @param String notificationId
  /// @param String channelType
  /// @param Array messageTypes
  RegistrarConnector(
      {this.channelType,
      this.context,
      this.transport,
      NotificationsConfiguration config})
      : super(config);

  final NotificationChannelType channelType;
  Map<String, dynamic> context = {};
  final transport;
  String registrationId;

  final BackoffRetrierConfig retrierConfig =
      BackoffRetrierConfig(min: 2000, max: 120000, randomness: 0.2);

  @override
  Future<RegistrationState> updateRegistration(RegistrationState registration,
      Set<NotificationUpdateReason> reasons) async {
    if (reasons.contains('notificationId')) {
      await removeRegistration();
    }
    if (registration.notificationId == null ||
        registration.notificationId.isEmpty) {
      return registration;
    }
    await register(registration);
    return registration;
  }

  @override
  Future removeRegistration() async {
    if (registrationId == null) {
      return null;
    }
    final url =
        '${config.url}/$registrationId?productId=${context['productId']}';
    final headers = {
      'Content-Type': 'application/json',
      'X-Twilio-Token': config.token
    };
    try {
      //_1.log.trace('Removing registration for ', channelType);
      Retrier(
              maxAttemptsCount: 3,
              minDelay: retrierConfig.min,
              maxDelay: retrierConfig.max,
              randomness: retrierConfig.randomness)
          .run(() => transport.delete(url, headers));
      //_1.log.debug('Registration removed for', channelType);
    } catch (err) {
      //_1.log.error('Failed to remove of registration ', channelType, err);
      rethrow;
    }
  }

  Future register(RegistrationState registration) async {
    //_1.log.trace('Registering', channelType, registration);
    final registrarRequest = {
      'endpoint_platform': context['platform'],
      'channel_type': channelType,
      'version': context['protocolVersion'].toString(),
      'message_types': List.from(registration.messageTypes),
      'data': {'registration_id': registration.notificationId},
      'ttl': 'PT24H'
    };
    final url = '${config.url}?productId=${context['productId']}';
    final headers = {
      'Content-Type': 'application/json',
      'X-Twilio-Token': registration.token
    };
    //_1.log.trace('Creating registration for channel ', channelType);
    try {
      Retrier(
              minDelay: retrierConfig.min,
              maxDelay: retrierConfig.max,
              randomness: retrierConfig.randomness)
          .run(() {
        final response = transport.post(url, headers, registrarRequest);
        registrationId = response.data['id'];
      });

      //_1.log.debug('Registration created: ', response);
    } catch (err) {
      //_1.log.error('Registration failed: ', err);
      rethrow;
    }
  }
}
