import 'package:twilio_conversations/src/enum/sync/open_mode.dart';

class OpenOptions {
  OpenOptions({this.ttl, this.id, this.mode});
  String id;
  OpenMode mode;
  int ttl;
}

class OpenDocumentOptions extends OpenOptions {
  Map<String, dynamic> data;
}

class OpenListOptions extends OpenOptions {
  String purpose;
  Map<String, dynamic> context;
  bool includeItems;
}

class OpenMapOptions extends OpenOptions {
  bool includeItems;
}

class OpenStreamOptions extends OpenOptions {}
