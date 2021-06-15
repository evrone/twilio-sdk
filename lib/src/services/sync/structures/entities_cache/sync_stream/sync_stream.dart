import 'package:twilio_conversations/src/services/sync/core/closable.dart';

import 'core/sync_stream_implementation.dart';
import 'models/stream_links.dart';

/// @class
/// @alias Stream
/// @classdesc A Sync primitive for pub-sub messaging. Stream Messages are not persisted, exist
///     only in transit, and will be dropped if (due to congestion or network anomalies) they
///     cannot be delivered promptly. Use the {@link Client#stream} method to obtain a reference to a Sync Message Stream.
/// Information about rate limits can be found {@link https://www.twilio.com/docs/sync/limits|here}.
/// @property {String} sid The immutable system-assigned identifier of this stream. Never null.
/// @property {String} [uniqueName=null] A unique identifier optionally assigned to the stream on creation.
///
/// @fires Stream#messagePublished
/// @fires Stream#removed
class SyncStream extends Closeable {
  SyncStream(this.syncStreamImpl) : super() {
    syncStreamImpl.attach(this);
  }

  SyncStreamImpl syncStreamImpl;
// private props
  String get uri => syncStreamImpl.uri;
  StreamLinks get links => syncStreamImpl.links;

  static String get type => SyncStreamImpl.Type;
  DateTime get dateExpires => syncStreamImpl.dateExpires;

  int get lastEventId => null;
// public props, documented along with class description
  String get sid => syncStreamImpl.sid;

  String get uniqueName => syncStreamImpl.uniqueName;

  /// Publish a Message to the Stream. The system will attempt delivery to all online subscribers.
  /// @param {Object} value The body of the dispatched message. Maximum size in serialized JSON: 4KB.
  /// A rate limit applies to this operation, refer to the [Sync API documentation]{@link https://www.twilio.com/docs/api/sync} for details.
  /// @return {Promise<StreamMessage>} A promise which resolves after the message is successfully published
  ///   to the Sync service. Resolves irrespective of ultimate delivery to any subscribers.
  /// @public
  /// @example
  /// stream.publishMessage({ x: 42, y: 123 })
  ///   .then(function(message) {
  ///     console.log('Stream publishMessage() successful, message SID:' + message.sid);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Stream publishMessage() failed', error);
  ///   });
  Future<Map<String, dynamic>> publishMessage(
      Map<String, dynamic> value) async {
    ensureNotClosed();
    return syncStreamImpl.publishMessage(value);
  }

  /// Update the time-to-live of the stream.
  /// @param {Number} ttl Specifies the TTL in seconds after which the stream is subject to automatic deletion. The value 0 means infinity.
  /// @return {Promise<void>} A promise that resolves after the TTL update was successful.
  /// @public
  /// @example
  /// stream.setTtl(3600)
  ///   .then(function() {
  ///     console.log('Stream setTtl() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Stream setTtl() failed', error);
  ///   });
  void setTtl(int ttl) {
    ensureNotClosed();
    return syncStreamImpl.setTtl(ttl);
  }

  /// Permanently delete this Stream.
  /// @return {Promise<void>} A promise which resolves after the Stream is successfully deleted.
  /// @public
  /// @example
  /// stream.removeStream()
  ///   .then(function() {
  ///     console.log('Stream removeStream() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Stream removeStream() failed', error);
  ///   });
  void removeStream() {
    ensureNotClosed();
    syncStreamImpl.removeStream();
  }

  /// Conclude work with the stream instance and remove all event listeners attached to it.
  /// Any subsequent operation on this object will be rejected with error.
  /// Other local copies of this stream will continue operating and receiving events normally.
  /// @public
  /// @example
  /// stream.close();
  @override
  void close() {
    super.close();
    syncStreamImpl.detach(listenerUuid);
  }
}

///
/// @class StreamMessage
/// @classdesc Stream Message descriptor.
/// @property {String} sid Contains Stream Message SID.
/// @property {Object} value Contains Stream Message value.
///
///
/// Fired when a Message is published to the Stream either locally or by a remote actor.
/// @event Stream#messagePublished
/// @param {Object} args Arguments provided with the event.
/// @param {StreamMessage} args.message Published message.
/// @param {Boolean} args.isLocal Equals 'true' if message was published by local code, 'false' otherwise.
/// @example
/// stream.on('messagePublished', function(args) {
///   console.log('Stream message published');
///   console.log('Message SID: ' + args.message.sid);
///   console.log('Message value: ', args.message.value);
///   console.log('args.isLocal:', args.isLocal);
/// });
///
///
/// Fired when a stream is removed entirely, whether the remover was local or remote.
/// @event Stream#removed
/// @param {Object} args Arguments provided with the event.
/// @param {Boolean} args.isLocal Equals 'true' if stream was removed by local code, 'false' otherwise.
/// @example
/// stream.on('removed', function(args) {
///   console.log('Stream ' + stream.sid + ' was removed');
///   console.log('args.isLocal:', args.isLocal);
/// });
///
