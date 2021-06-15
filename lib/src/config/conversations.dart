import 'package:twilio_conversations/src/abstract_classes/configuration.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';

const TYPING_PATH = '/v1/typing';
const TYPING_TIMEOUT = 5;
const HTTP_CACHE_LIFETIME = 'PT5S';
const CONSUMPTION_HORIZON_SENDING_INTERVAL = 'PT5S';
const USER_INFOS_TO_SUBSCRIBE = 100;
const MINIMUM_RETRY_DELAY = 1000;
const MAXIMUM_RETRY_DELAY = 4000;
const MAXIMUM_ATTEMPTS_COUNT = 3;
const RETRY_WHEN_THROTTLED = true;

class ConversationsConfiguration implements Configuration {
  ConversationsConfiguration(
      {this.region,
      String apiUri,
      this.typingIndicatorTimeoutOverride,
      this.httpCacheIntervalOverride,
      this.consumptionReportIntervalOverride,
      this.userInfosToSubscribeOverride,
      this.retryWhenThrottledOverride,
      this.backoffConfigOverride,
      this.productId})
      : _baseUrl = apiUri ?? (region == null || region == 'us1')
            ? 'https://aim.twilio.com'
            : 'https://aim.$region.twilio.com' {
    _typingIndicatorUri = url + TYPING_PATH;
  }

  String token;
  final int typingIndicatorTimeoutOverride;
  final String httpCacheIntervalOverride;
  final int consumptionReportIntervalOverride;
  final int userInfosToSubscribeOverride;
  final bool retryWhenThrottledOverride;
  final BackoffRetrierConfig backoffConfigOverride;
  String _typingIndicatorUri;
  String get typingIndicatorUri => _typingIndicatorUri;
  final String productId;
  final String _baseUrl;
  @override
  String get url => _baseUrl;
  final String region;

  int get typingIndicatorTimeoutDefault => TYPING_TIMEOUT * 1000;
  String get httpCacheIntervalDefault => HTTP_CACHE_LIFETIME;
  String get consumptionReportIntervalDefault =>
      CONSUMPTION_HORIZON_SENDING_INTERVAL;
  int get userInfosToSubscribeDefault => USER_INFOS_TO_SUBSCRIBE;
  bool get retryWhenThrottledDefault => RETRY_WHEN_THROTTLED;
  BackoffRetrierConfig get backoffConfigDefault {
    return BackoffRetrierConfig(
        min: MINIMUM_RETRY_DELAY,
        max: MAXIMUM_RETRY_DELAY,
        maxAttemptsCount: MAXIMUM_ATTEMPTS_COUNT);
  }
}
