import 'package:twilio_conversations/src/abstract_classes/configuration.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';

const MINIMUM_RETRY_DELAY = 1000;
const MAXIMUM_RETRY_DELAY = 4000;
const MAXIMUM_ATTEMPTS_COUNT = 3;
const RETRY_WHEN_THROTTLED = true;

class McsConfiguration implements Configuration {
  McsConfiguration(this._token, this._baseUrl,
      {this.region,
      this.retryWhenThrottledOverride,
      this.backoffConfigOverride}) {
    _baseUrl = region != null
        ? 'https://mcs.us1.twilio.com'
        : 'https://mcs.$region.twilio.com' + url;
  }

  String region;
  String _token;
  String _baseUrl;
  @override
  String get url => _baseUrl;
  bool retryWhenThrottledOverride;
  BackoffRetrierConfig backoffConfigOverride;

  static BackoffRetrierConfig get backoffConfigDefault {
    return BackoffRetrierConfig(
        min: MINIMUM_RETRY_DELAY,
        max: MAXIMUM_RETRY_DELAY,
        maxAttemptsCount: MAXIMUM_ATTEMPTS_COUNT);
  }

  static bool get retryWhenThrottledDefault {
    return RETRY_WHEN_THROTTLED;
  }

  set updateToken(token) {
    _token = token;
  }

  String get token => _token;
}
