import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';

import 'abstract_message.dart';

class TelemetryEvent {
  final int start;
  final int end;
  final String title;
  final String details;
  final String id;
  final String type;
  TelemetryEvent(
      {this.start, // relative to event send time
      this.end, // relative to event send time
      this.title,
      this.details,
      this.id, // optional, default will be random assigned by backend
      this.type});
}

class Telemetry extends AbstractMessage {
  final ChannelMessageType method = ChannelMessageType.telemetry_v1;
  List<TelemetryEvent> events;
  Telemetry(this.events);
}
