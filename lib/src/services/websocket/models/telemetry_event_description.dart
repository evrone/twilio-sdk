import 'messages/telemetry.dart';

class TelemetryEventDescription {
  String title;
  String details;
  DateTime start;
  String type;
  String id;
  DateTime end;
  TelemetryEventDescription(
      {this.title, this.details, this.start, this.end, this.type, this.id});
  TelemetryEvent toTelemetryEvent() {
    // Fix dates
    final now = DateTime.now();
    var actualStart = start;
    var actualEnd = end ?? now;
    if (actualEnd.isBefore(actualStart)) {
      final tmp = actualEnd;
      actualEnd = actualStart;
      actualStart = tmp;
    }
    // Converting dates to relative offset from current moment in ms
    final startOffset =
        actualStart.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    final endOffset =
        actualEnd.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    final result = TelemetryEvent(
        start: startOffset,
        end: endOffset,
        title: title,
        details: details,
        id: id,
        type: type);
    return result;
  }
}
