import 'package:twilio_conversations/src/abstract_classes/configuration.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';

const SUBSCRIPTIONS_PATH = '/v4/Subscriptions';
const MAPS_PATH = '/v3/Maps';
const LISTS_PATH = '/v3/Lists';
const DOCUMENTS_PATH = '/v3/Documents';
const STREAMS_PATH = '/v3/Streams';
const INSIGHTS_PATH = '/v3/Insights';
dynamic getWithDefault(Map container, key, defaultValue) {
  if (container[key] != null) {
    return container[key];
  }
  return defaultValue;
}

class SyncSettings {
  SyncSettings(
      {this.insightsUri,
      this.backoffConfig,
      this.productId,
      this.documentsUri,
      this.listsUri,
      this.mapsUri,
      this.sessionStorageEnabled,
      this.streamsUri,
      this.subscriptionsUri});
  final String subscriptionsUri;
  final String documentsUri;
  final String listsUri;
  final String mapsUri;
  final String streamsUri;
  final String insightsUri;
  final String productId;
  final BackoffRetrierConfig backoffConfig;
  final bool sessionStorageEnabled;
}

/// Settings container for Sync library
class SyncConfiguration implements Configuration {
  /// @param {Object} options
  SyncConfiguration(
      {this.region = 'us1', String cdsUri, Map Sync, String productId})
      : _baseUri = cdsUri ?? 'https://cds.$region.twilio.com' {
    _settings = SyncSettings(
      subscriptionsUri: _baseUri + SUBSCRIPTIONS_PATH,
      documentsUri: _baseUri + DOCUMENTS_PATH,
      listsUri: _baseUri + LISTS_PATH,
      mapsUri: _baseUri + MAPS_PATH,
      streamsUri: _baseUri + STREAMS_PATH,
      insightsUri: _baseUri + INSIGHTS_PATH,
      sessionStorageEnabled: getWithDefault(Sync, 'enableSessionStorage', true),
      productId: productId,
    );
  }

  SyncSettings _settings;
  final String region;
  final String _baseUri;
  @override
  String get url => _baseUri;

  String get subscriptionsUri => _settings.subscriptionsUri;

  String get documentsUri => _settings.documentsUri;

  String get listsUri => _settings.listsUri;

  String get mapsUri => _settings.mapsUri;

  String get streamsUri => _settings.streamsUri;

  String get insightsUri => _settings.insightsUri;

  BackoffRetrierConfig get backoffConfig => _settings.backoffConfig;

  bool get sessionStorageEnabled => _settings.sessionStorageEnabled;

  String get productId => _settings.productId;
}
