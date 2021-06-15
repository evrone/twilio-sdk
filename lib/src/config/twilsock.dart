import 'package:twilio_conversations/src/abstract_classes/configuration.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';

import '../services/websocket/models/init_registration.dart';

const packageVersion = '0.6.2';

/// Settings container for the Twilsock client library
class TwilsockConfiguration implements Configuration {
  /// @param {String} token - authentication token
  /// @param {Object} options - options to override defaults
  TwilsockConfiguration(this._token, this.activeGrant,
      {String region = 'us1',
      this.twilsockOptions,
      String continuationToken,
      this.clientMetadata,
      logLevel = 'error',
      this.initRegistrations,
      this.tweaks,
      BackoffRetrierConfig rtyPolicy})
      : _continuationToken = continuationToken {
    final defaultTwilsockUrl = 'wss://tsock.$region.twilio.com/v3/wsconnect';
    _url = twilsockOptions['uri'] ?? defaultTwilsockUrl;

    retryPolicy = rtyPolicy ??
        BackoffRetrierConfig(
            min: 1 * 1000, max: 2 * 60 * 1000, randomness: 0.2);

    clientMetadata['ver'] = packageVersion;
  }
  List<InitRegistration> initRegistrations = [];
  final tweaks;
  final twilsockOptions;
  final String _continuationToken;
  String _url;
  @override
  String get url => _url;
  BackoffRetrierConfig retryPolicy;
  Map<String, dynamic> clientMetadata;
  String logLevel;
  var confirmedCapabilities = <String>{};
  String _token;
  final String activeGrant;

  String get token => _token;
  String get continuationToken => _continuationToken;
  void updateToken(token) {
    _token = token;
  }

  set updateContinuationToken(continuationToken) {
    continuationToken = continuationToken;
  }
}
