import 'package:uuid/uuid.dart';

class AbstractMessage {
  String id;
  AbstractMessage({String id}) {
    id ??= 'TM${Uuid().v4()}';
  }

  Map<String, dynamic> toMap() => {'id': id};
}
