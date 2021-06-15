import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/core/router.dart';
import 'package:twilio_conversations/src/services/sync/removal_handler/removal_handler.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_stream/models/stream_links.dart';

import '../../entity.dart';

class SyncStreamImpl extends SyncEntity {
  /// @private
  SyncStreamImpl(
    RemovalHandler removalHandler, {
    SyncNetwork network,
    SyncRouter router,
    Storage storage,
    String sid,
    String uniqueName,
    String url,
    DateTime dateExpires,
    StreamLinks links,
  })  : _network = network,
        _dateExpires = dateExpires,
        _links = links,
        _url = url,
        _sid = sid,
        _uniqueName = uniqueName,
        super(removalHandler,
            network: network, storage: storage, router: router);

  final String _sid;
  final String _uniqueName;
  final String _url;
  DateTime _dateExpires;
  final StreamLinks _links;
  final SyncNetwork _network;

  // private props
  String get uri => _url;

  StreamLinks get links => _links;

  static String get Type => 'stream';
  @override
  String get type => 'stream';

  DateTime get dateExpires => _dateExpires;

  @override
  int get lastEventId => null;

  // below properties are specific to Insights only
  @override
  String get indexName => null;
  @override
  String get queryString => null;

  // public props, documented along with class description
  @override
  String get sid => _sid;

  @override
  String get uniqueName => _uniqueName;

  Future<Map<String, dynamic>> publishMessage(
      Map<String, dynamic> value) async {
    final requestBody = {'data': value};
    final response = await _network.post(links.messages, body: requestBody);
    final responseBody = response.data;
    final event = _handleMessagePublished(responseBody.sid, value, false);
    return event;
  }

  void setTtl(int ttl) async {
    try {
      final requestBody = {'ttl': ttl};
      final response = await _network.post(uri, body: requestBody);
      _dateExpires = DateTime.tryParse(response.data['date_expires']);
    } catch (error) {
      if (error.status == 404) {
        onRemoved(false);
      }
      rethrow;
    }
  }

  void removeStream() async {
    await _network.delete(uri);
    onRemoved(true);
  }

  /// Handle event from the server
  /// @private
  @override
  void update(Map<String, dynamic> update, {bool isStrictlyOrdered}) {
    switch (update['type']) {
      case 'stream_message_published':
        {
          _handleMessagePublished(
              update['message_sid'], update['message_data'], true);
          break;
        }
      case 'stream_removed':
        {
          onRemoved(false);
          break;
        }
    }
  }

  Map<String, dynamic> _handleMessagePublished(
      String sid, Map<String, dynamic> data, bool remote) {
    final event = {'sid': sid, 'value': data};
    broadcastEventToListeners(
        'messagePublished', {'message': event, 'isLocal': !remote});
    return event;
  }

  @override
  void onRemoved(bool isLocal) {
    unsubscribe();
    removalHandler(type, sid, uniqueName);
    broadcastEventToListeners('removed', {'isLocal': isLocal});
  }

  @override
  void advanceLastEventId(int eventId, {String revision}) {
    // TODO: implement advanceLastEventId
  }
}
