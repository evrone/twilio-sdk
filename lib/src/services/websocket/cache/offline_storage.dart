import 'package:twilio_conversations/src/errors/twilsockerror.dart';

class OfflineProductStorage {
  String id;
  OfflineProductStorage(this.id);
  static OfflineProductStorage create(Map<String, dynamic> productPayload) {
    if (productPayload['storage_id'] != null) {
      return OfflineProductStorage(productPayload['storage_id']);
    } else {
      throw TwilsockError('Field "storage_id" is missing');
    }
  }
}
