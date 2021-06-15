import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/config/conversations.dart';
import 'package:twilio_conversations/src/enum/notification/channel_type.dart';
import 'package:twilio_conversations/src/services/notifications/client.dart';
import 'package:twilio_conversations/src/services/websocket/client.dart';

import '../const/notificationtypes.dart';

///
/// An important note in regards to typing timeout timers. There are two places that the SDK can get the 'typing_timeout' attribute from. The first
/// place that the attribute appears in is the response received from POST -> /v1/typing REST call. In the body of that response, the value of the
/// 'typing_timeout' attribute will be exactly the same as defined in the console. The second place that the attribute appears in is from a
/// notification of type 'twilio.ipmsg.typing_indicator'. In this case, the 'typing_timeout' value will be +1 of that in the console. This
/// intentional. The timeout returned from the POST -> /v1/typing call should be used to disable further calls for that period of time. On contrary,
/// the timeout returned from the notification should be used as the timeout for the 'typingEnded' event, +1 is to account for latency.
///
/// @private
///
/// @class TypingIndicator
///
/// @constructor
/// @private
class TypingIndicator {
  TypingIndicator(this.config, this.getConversation,
      {TwilsockClient transport, NotificationsClient notificationClient})
      : _transport = transport,
        _notificationClient = notificationClient;

  ConversationsConfiguration config;
  final TwilsockClient _transport;
  final NotificationsClient _notificationClient;
  Function getConversation;
  int serviceTypingTimeout;
  Map<String, DateTime> sentUpdates = {};

  int get typingTimeout {
    return config.typingIndicatorTimeoutOverride ??
        serviceTypingTimeout ??
        config.typingIndicatorTimeoutDefault;
  }

  /// Initialize TypingIndicator controller
  /// Registers for needed message types and sets listeners
  /// @private
  void initialize() {
    _notificationClient.subscribe(NotificationTypes.TYPING_INDICATOR,
        channelType: NotificationChannelType.twilsock);
    _notificationClient.on('message', (payload) {
      if (payload['type'] == NotificationTypes.TYPING_INDICATOR) {
        handleRemoteTyping(payload['message']);
      }
    });
  }

  /// Remote participants typing events handler
  /// @private
  void handleRemoteTyping(Map<String, dynamic> message) {
    //log.trace('Got new typing indicator ', message);
    getConversation(message['channel_sid']).then((conversation) {
      if (conversation == null) {
        return;
      }
      conversation.participants.forEach((participant) {
        if (participant.identity != message['identity']) {
          return;
        }
        final timeout = config.typingIndicatorTimeoutOverride + 1000 ??
            message['typing_timeout'] * 1000;
        participant._startTyping(timeout);
      });
    });
  }

  /// Send typing event for the given conversation sid
  /// @param {String} conversationSid
  Future<Response> send(String conversationSid) async {
    final lastUpdate = sentUpdates[conversationSid];
    if (lastUpdate != null &&
        lastUpdate.isBefore(
            DateTime.now().subtract(Duration(milliseconds: typingTimeout)))) {
      return null;
    }
    sentUpdates[conversationSid] = DateTime.now();
    return _send(conversationSid);
  }

  Future<Response> _send(String conversationSid) async {
    // log.trace('Sending typing indicator');
    final url = config.typingIndicatorUri;
    final headers = {'Content-Type': 'application/x-www-form-urlencoded'};
    final body = 'ChannelSid=' + conversationSid;
    var response;
    try {
      response = await _transport.post(url, headers, body, config.productId);
    } catch (err) {
      //log.error('Failed to send typing indicator:', err);
      rethrow;
    }
    if (response.data['typing_timeout'] != null) {
      serviceTypingTimeout = response.data['typing_timeout'] * 1000;
    }
    return response;
  }
}
