import 'package:twilio_conversations/src/enum/twilsock/capabilities.dart';
import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';

import '../init_registration.dart';
import 'abstract_message.dart';

class Init extends AbstractMessage {
  final ChannelMessageType method = ChannelMessageType.init;
  final String token;
  final String continuationToken;
  final List<TwilsockCapabilities> capabilities = [
    TwilsockCapabilities.clientUpdate,
    TwilsockCapabilities.offlineStorage,
    TwilsockCapabilities.telemetry_v1
  ];
  Map<String, String> metadata;
  List<InitRegistration> registrations;
  Map tweaks;
  Init(this.token, this.continuationToken, this.metadata, this.registrations,
      this.tweaks);
}
