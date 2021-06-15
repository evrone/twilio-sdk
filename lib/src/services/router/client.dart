import 'package:dio/dio.dart';

import '../../config/mcs_client.dart';
import 'models/media.dart';
import 'network/network.dart';
import 'network/transport.dart';

const SDK_VERSION = '0.3.3';
const MSG_NO_TOKEN = 'A valid Twilio token should be provided';

/// @classdesc A Client provides an interface for Media Content Service
class McsClient {
  /// @param {String} token - Access token
  /// @param {String} baseUrl - Base URL for Media Content Service, i.e. /v1/Services/{serviceSid}/Media
  /// @param {Client#ClientOptions} [options] - Options to customize the Client
  McsClient(String token, String baseUrl,
      {String region, McsTransport transport})
      : _config = McsConfiguration(token, baseUrl, region: region) {
    //options.logLevel = options.logLevel || 'silent';
    _network = McsNetwork(_config, transport ?? McsTransport());
    if (token == null) {
      throw Exception(MSG_NO_TOKEN);
    }
    //log.setLevel(options.logLevel);
  }

  final McsConfiguration _config;
  McsNetwork _network;

  ///
  /// These options can be passed to Client constructor
  /// @typedef {Object} Client#ClientOptions
  /// @property {String} [logLevel='error'] - The level of logging to enable. Valid options
  ///   (from strictest to broadest): ['silent', 'error', 'warn', 'info', 'debug', 'trace']
  ///
  /// Update the token used for Client operations
  /// @param {String} token - The JWT String of the new token
  /// @public
  /// @returns {void}
  void updateToken(String token) {
    //log.info('updateToken');
    if (token == null) {
      throw Exception(MSG_NO_TOKEN);
    }
    _config.updateToken = token;
  }

  /// Gets media from media service
  /// @param {String} sid - Media's SID
  /// @public
  /// @returns {Future<Media>}
  Future<McsMedia> get(sid) async {
    final response = await _network.get('${_config.url}/$sid');
    return McsMedia(_config, _network, response);
  }

  /// Posts raw content to media service
  /// @param {String} contentType - content type of media
  /// @param {String|Buffer} media - content to post
  /// @public
  /// @returns {Future<Media>}
  Future<McsMedia> post(String contentType, media) async {
    final response = await _network.post(_config.url,
        media: media, contentType: contentType);
    return McsMedia(_config, _network, response);
  }

  /// Posts FormData to media service. Can be used only with browser engine's FormData.
  /// In non-browser FormData case the method will do promise reject with
  /// new TypeError('Posting FormData supported only with browser engine's FormData')
  /// @param {FormData} formData - form data to post
  /// @public
  /// @returns {Promise<Media>}
  Future<McsMedia> postFormData(FormData formData) async {
    final response = await _network.post(_config.url, media: formData);
    return McsMedia(_config, _network, response);
  }
}
