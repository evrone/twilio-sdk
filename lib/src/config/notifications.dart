import 'package:twilio_conversations/src/abstract_classes/configuration.dart';

class NotificationsConfiguration implements Configuration {
  NotificationsConfiguration(String token,
      {notifications, String region = 'us1'})
      : _token = token {
    final reg = notifications.region ?? region;
    final defaultUrl = 'https://ers.$reg.twilio.com/v1/registrations';
    _url = notifications.ersUrl ?? defaultUrl;
  }

  String _token;
  String _url;
  @override
  String get url => _url;

  set updateToken(String token) {
    _token = token;
  }

  String get token {
    return _token;
  }
}
