import 'package:twilio_conversations/src/services/router/client.dart';
import 'package:twilio_conversations/src/services/router/models/media.dart';

class MediaState {
  MediaState({this.sid, this.filename, this.contentType, this.size});
  String sid;
  String filename;
  String contentType;
  int size;
}

class MediaServices {
  MediaServices({this.mcsClient});
  McsClient mcsClient;
}

/// @classdesc A Media represents a media information for Message in a Conversation.
/// @property {String} contentType - content type of media
/// @property {String} sid - The server-assigned unique identifier for Media
/// @property {Number} size - Size of media, bytes
/// @property {String} [filename] - file name if present, null otherwise
class Media {
  MediaState _state;
  MediaServices services;
  McsMedia mcsMedia;
  Media({MediaState data, this.services}) : _state = data;
  String get sid => _state.sid;
  String get filename => _state.filename;
  String get contentType => _state.contentType;
  int get size => _state.size;

  /// Returns direct content URL for the media.
  ///
  /// This URL is impermanent, it will expire in several minutes and cannot be cached.
  /// If the URL becomes expired, you need to request a new one.
  /// Each call to this produces a new temporary URL.
  ///
  /// @returns {Future<String>}
  Future<String> getContentTemporaryUrl() async {
    if (mcsMedia == null) {
      if (services.mcsClient == null) {
        mcsMedia = await services.mcsClient.get(_state.sid);
      } else {
        throw Exception('Media Content Service is unavailable');
      }
    }
    return mcsMedia.getContentUrl();
  }
}
