import 'dart:math';

import 'package:twilio_conversations/src/enum/twilsock/capabilities.dart';
import 'package:twilio_conversations/src/enum/twilsock/event_sending_limitation.dart';
import 'package:twilio_conversations/src/enum/twilsock/telemetry_point.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/telemetry.dart';
import 'package:twilio_conversations/src/services/websocket/models/telemetry_event_description.dart';

import 'packet_interface.dart';

class TelemetryTracker {
  TelemetryTracker(this.config, this.packetInterface);

  /// accumulated events count that is big enough to be sent out of schedule (not on timer but on new event registration)
  final minEventsPortionToSend = 50;

  /// max events batch size to be sent in a single Telemetry message
  final maxEventsPortionToSend = 100;
  final config;
  final PacketInterface packetInterface;

  /// started events: have TelemetryEvent::startTime only
  Map<String, TelemetryEventDescription> pendingEvents = {};

  /// events ready to send
  List<TelemetryEventDescription> readyEvents = [];
  bool hasInitializationFinished = false;
  bool _canSendTelemetry = false;

  bool get isTelemetryEnabled =>
      config.confirmedCapabilities.contains(TwilsockCapabilities.telemetry_v1);
  bool get canSendTelemetry => _canSendTelemetry && isTelemetryEnabled;
  set canSendTelemetry(bool enable) {
    //logger_1.log.debug(`TelemetryTracker.canSendTelemetry: ${enable} TelemetryTracker.isTelemetryEnabled: ${this.isTelemetryEnabled}`);
    // We want to keep telemetry events added in advance but
    // we need to purge events from previous connection when being disconnected
    if (_canSendTelemetry && !enable) {
      pendingEvents.clear();
      readyEvents.clear();
    }
    _canSendTelemetry = enable;
    if (enable) {
      sendTelemetry(EventSendingLimitation.AnyEvents);
    }
    if (enable && !hasInitializationFinished) {
      hasInitializationFinished = true;
    }
  }

  void addTelemetryEvent(TelemetryEventDescription event) {
    // Allow adding events before initialization.
    if (!canSendTelemetry && hasInitializationFinished) {
      return;
    }
    readyEvents.add(event);
  }

  void addPartialEvent(TelemetryEventDescription incompleteEvent,
      String eventKey, TelemetryPoint point) {
    //logger_1.log.debug(`Adding ${point === TelemetryPoint.Start ? 'starting' : 'ending'} timepoint for '${eventKey}' event`);
    final exists = pendingEvents.containsKey(eventKey);
    if (point == TelemetryPoint.Start) {
      if (exists) {
        //logger_1.log.debug(`Overwriting starting point for '${eventKey}' event`);
      }
      pendingEvents[eventKey] = incompleteEvent;
    } else {
      if (!exists) {
        //logger_1.log.info(`Could not find started event for '${eventKey}' event`);
        return;
      }
      addTelemetryEvent(merge(pendingEvents[eventKey], incompleteEvent));
      pendingEvents.remove(eventKey);
    }
  }

  List<TelemetryEventDescription> getTelemetryToSend(
      EventSendingLimitation sendingLimit) {
    if (!canSendTelemetry || readyEvents.isEmpty) {
      return []; // Events are collected but not sent until telemetry is enabled
    }
    if (sendingLimit == EventSendingLimitation.MinEventsPortion &&
        readyEvents.length < minEventsPortionToSend) {
      return [];
    }
    return getTelemetryPortion(
        sendingLimit == EventSendingLimitation.AnyEventsIncludingUnfinished);
  }

  List<TelemetryEventDescription> getTelemetryPortion(bool includeUnfinished) {
    final eventsPortionToSend =
        min<int>(readyEvents.length, maxEventsPortionToSend);
    final res = [...readyEvents.getRange(0, eventsPortionToSend)];
    readyEvents.removeRange(0, eventsPortionToSend);
    if (includeUnfinished && res.length < maxEventsPortionToSend) {
      pendingEvents.forEach((value, key) {
        if (res.length >= maxEventsPortionToSend) {
          return; // @fixme does not end the loop early
        }
        final event = pendingEvents[key];
        pendingEvents.remove(key);
        res.add(TelemetryEventDescription(
            title:
                '[UNFINISHED] ${event.title}', // add prefix title to mark unfinished events for CleanSock
            details: event.details,
            start: event.start,
            end: null, // Not ended, on sending will be replaced with now
            type: event.type,
            id: event.id));
      });
    }
    return res;
  }

  TelemetryEventDescription merge(
          TelemetryEventDescription start, TelemetryEventDescription end) =>
      TelemetryEventDescription(
          title: end.title ?? start.title,
          details: end.details ?? start.details,
          start: start.start,
          end: end.end,
          type: end.type ?? start.type,
          id: end.id ?? start.id);
  void sendTelemetryIfMinimalPortionCollected() {
    sendTelemetry(EventSendingLimitation.MinEventsPortion);
  }

  void sendTelemetry(EventSendingLimitation limit) {
    final events = getTelemetryToSend(limit);
    if (events.isEmpty) {
      return; // not enough telemetry data collected
    }
    try {
      packetInterface
          .send(Telemetry(events.map((el) => el.toTelemetryEvent())));
    } catch (err) {
      //logger_1.log.debug(`Error while sending ${events.length} telemetry events due to ${err}; they will be resubmitted`);
      readyEvents = [...readyEvents, ...events];
    }
  }
}
