import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/config/mcs_client.dart';
import 'package:twilio_conversations/src/services/router/models/media_state.dart';
import 'package:twilio_conversations/src/services/router/network/network.dart';

/// @classdesc A Media represents a metadata information for the media upload
/// @property {String} sid - The server-assigned unique identifier for Media
/// @property {String} serviceSid - Service instance id which Media belongs/uploaded to
/// @property {DateTime} dateCreated - When the Media was created
/// @property {DateTime} dateUpdated - When the Media was updated
/// @property {int} size - Size of media, bytes
/// @property {String} contentType - content type of media
/// @property {String} fileName - file name, if present, null otherwise
class McsMedia {
  McsMedia(this.config, this.network, Response data) {
    config = config;
    network = network;
    _update(data);
  }

  McsNetwork network;
  McsConfiguration config;

  McsMediaState _state;

  String get sid {
    return _state.sid;
  }

  String get serviceSid {
    return _state.serviceSid;
  }

  DateTime get dateCreated {
    return _state.dateCreated;
  }

  DateTime get dateUpdated {
    return _state.dateUpdated;
  }

  String get contentType {
    return _state.contentType;
  }

  double get size {
    return _state.size;
  }

  String get fileName {
    return _state.filename;
  }

  /// Returns direct content URL to uploaded binary
  /// @public
  /// @returns {Future<String>}
  Future<String> getContentUrl() async {
    final response = await network.get('${config.url}/$sid');
    _update(response);
    return _state.contentDirectUrl;
  }

  void _update(Response response) {
    _state = McsMediaState(
        sid: response.data['sid'],
        serviceSid: response.data['service_sid'],
        channelSid: response.data['channel_sid'],
        messageSid: response.data['message_sid'],
        dateCreated: response.data['date_created'] != null
            ? DateTime.tryParse(response.data['date_created'])
            : null,
        dateUpdated: response.data['date_updated'] != null
            ? DateTime.tryParse(response.data['date_updated'])
            : null,
        size: response.data['size'],
        contentType: response.headers.value('Content-Type'),
        url: response.data['url'],
        contentUrl: response.data['links']['content'],
        contentDirectUrl: response.data['links']['content_direct_temporary'],
        filename: response.data['filename']);
  }
}
