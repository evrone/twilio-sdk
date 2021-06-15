import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/errors/syncerror.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/merging/merging_queue.dart';
import 'package:twilio_conversations/src/services/sync/core/router.dart';
import 'package:twilio_conversations/src/services/sync/removal_handler/removal_handler.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/models/entity_metadata.dart';
import 'package:twilio_conversations/src/utils/sanitizer.dart';

import '../../entity.dart';

class SyncDocumentImpl extends SyncEntity {
  /// @private
  SyncDocumentImpl(RemovalHandler removalHandler,
      {SyncNetwork network,
      SyncRouter router,
      Storage storage,
      String url,
      String sid,
      String revision,
      int lastEventId,
      String uniqueName,
      Map data,
      DateTime dateUpdated,
      String dateExpires})
      : _network = network,
        _storage = storage,
        _data = data,
        _revision = revision,
        _dateExpires = dateExpires,
        _dateUpdated = dateUpdated,
        _uniqueName = uniqueName,
        _lastEventId = lastEventId,
        _sid = sid,
        _url = url,
        super(removalHandler,
            network: network, router: router, storage: storage) {
    _updateMergingQueue = MergingQueue(_updateRequestReducer);
  }

  MergingQueue _updateMergingQueue;
  final SyncNetwork _network;
  final Storage _storage;
  final String _url;
  final String _sid;
  String _revision;
  int _lastEventId;
  final String _uniqueName;
  Map<String, dynamic> _data;
  DateTime _dateUpdated;
  String _dateExpires;
  final Function _updateRequestReducer =
      (acc, input) => (input.ttl is int) ? {'ttl': input.ttl} : acc;
  bool isDeleted = false;
// private props
  String get uri => _url;

  String get revision => _revision;

  @override
  int get lastEventId => _lastEventId;

  String get dateExpires => _dateExpires;

  @override
  String get type => 'document';
  static String get staticType => 'document';

// below properties are specific to Insights only
  @override
  String get indexName => null;
  @override
  String get queryString => null;

// public props, documented along with class description
  @override
  String get sid => _sid;
  Map<String, dynamic> get data => _data;

  DateTime get dateUpdated => _dateUpdated;

  @override
  String get uniqueName => _uniqueName;

  /// Update data entity with new data
  /// @private
  @override
  void update(Map<String, dynamic> update, {bool isStrictlyOrdered}) {
    //update.dateCreated = new DateTime(update.date_created);
    switch (update['type']) {
      case 'document_updated':
        if (update['id'] <= lastEventId) {
          // ('Document update skipped, current:', this.lastEventId, ', remote:', update.id);
          break;
        }
        final previousData = _data;
        _lastEventId = update['id'];
        _revision = update['document_revision'];
        _dateUpdated = DateTime.tryParse(update['date_created']);
        _data = update['document_data'];
        broadcastEventToListeners('updated', {
          'data': update['document_data'],
          'isLocal': false,
          'previousData': previousData
        });
        _storage.update(type, sid, uniqueName: uniqueName, patch: {
          'last_event_id': update['id'],
          'revision': update['document_revision'],
          'date_updated': update['date_created'],
          'data': update['document_data']
        });
        break;
      case 'document_removed':
        onRemoved(false);
        break;
    }
  }

  Future set(Map<String, dynamic> value, EntityMetadata metadataUpdates) async {
    final input = metadataUpdates ?? EntityMetadata();
    validateOptionalTtl(input.ttl);
    return await _updateMergingQueue.squashAndAdd(
        input, (input) => _setUnconditionally(value, input.ttl));
  }

  Future mutate(Function mutator, EntityMetadata metadataUpdates) async {
    final input = metadataUpdates ?? EntityMetadata();
    validateOptionalTtl(input.ttl);
    return await _updateMergingQueue.add(
        input, (input) => _setWithIfMatch(mutator, ttl: input.ttl));
  }

  Future updateMetadata(
      Map<String, dynamic> obj, EntityMetadata metadataUpdates) async {
    return await mutate((remote) => remote.addAll(data), metadataUpdates);
  }

  Future<void> setTtl(int ttl) async {
    validateMandatoryTtl(ttl);
    final response = await _postUpdateToServer(ttl: ttl);
    _dateExpires = response['date_expires'];
  }

  /// @private
  Future<Map<String, dynamic>> _setUnconditionally(
      Map<String, dynamic> value, int ttl) async {
    final result =
        await _postUpdateToServer(data: value, revision: null, ttl: ttl);
    _handleSuccessfulUpdateResult(
      sid: result['sid'],
      revision: result['revision'],
      lastEventId: result['last_event_id'],
      uniqueName: result['unique_name'],
      data: result['data'],
      dateUpdated: result['date_updated'],
      dateExpires: result['date_expires'],
    );
    return _data;
  }

  /// @private
  Future<Map<String, dynamic>> _setWithIfMatch(Function mutatorFunction,
      {int ttl}) async {
    final data = _data;
    if (data != null) {
      final revision = this.revision;
      try {
        final result =
            await _postUpdateToServer(data: data, revision: revision, ttl: ttl);
        _handleSuccessfulUpdateResult(
          sid: result['sid'],
          revision: result['revision'],
          lastEventId: result['last_event_id'],
          uniqueName: result['unique_name'],
          data: result['data'],
          dateUpdated: result['date_updated'],
          dateExpires: result['date_expires'],
        );
        return _data;
      } catch (error) {
        if (error.status == 412) {
          await _softSync();
          return _setWithIfMatch(mutatorFunction);
        }
      }
    }
    return _data;
  }

  /// @private
  void _handleSuccessfulUpdateResult(
      {String sid,
      String revision,
      int lastEventId,
      String uniqueName,
      Map<String, dynamic> data,
      DateTime dateUpdated,
      String dateExpires}) {
// Ignore returned value if we already got a newer one
    if (lastEventId <= _lastEventId) {
      return;
    }
    final previousData = _data;
    _revision = revision;
    _data = data;
    _lastEventId = lastEventId;
    _dateExpires = dateExpires;
    _dateUpdated = dateUpdated;
    _storage.update(type, sid, uniqueName: uniqueName, patch: {
      'last_event_id': lastEventId,
      'revision': revision,
      'date_updated': dateUpdated,
      'data': data
    });
    broadcastEventToListeners('updated',
        {'data': _data, 'isLocal': true, 'previousData': previousData});
  }

  /// @private
  Future<Map<String, dynamic>> _postUpdateToServer(
      {Map<String, dynamic> data, String revision, int ttl}) async {
    if (!isDeleted) {
      final Map<String, dynamic> requestBody = {'data': data};
      if (ttl != null) {
        requestBody['ttl'] = ttl;
      }

      try {
        final response =
            await _network.post(uri, body: requestBody, revision: revision);
        return {
          'revision': response.data['revision'],
          'data': data,
          'last_event_id': response.data['last_event_id'],
          'date_updated': response.data['date_updated'],
          'date_expires': response.data['date_expires']
        };
      } catch (error) {
        if (error.status == 404) {
          onRemoved(false);
        }
      }
    }
    return Future.error(
        SyncError('The Document has been removed', status: 404, code: 54100));
  }

  /// Get new data from server
  /// @private
  Future<SyncDocumentImpl> _softSync() async {
    final response = await _network.get(uri);
    try {
      final event = {
        'type': 'document_updated',
        'id': response.data['last_event_id'],
        'document_revision': response.data['revision'],
        'document_data': response.data['data'],
        'date_created': response.data['date_updated']
      };
      update(event);
      return this;
    } catch (e) {
      if (e.status == 404) {
        onRemoved(false);
      }

// (`Can't get updates for ${this.sid}:`, err);
      return null;
    }
  }

  @override
  void onRemoved(bool locally) {
    if (isDeleted) {
      return;
    }
    final previousData = _data;
    isDeleted = true;
    unsubscribe();
    removalHandler(type, sid, uniqueName);
    broadcastEventToListeners(
        'removed', {'isLocal': locally, 'previousData': previousData});
  }

  Future<void> removeDocument() async {
    if (!isDeleted) {
      await _network.delete(uri);
      onRemoved(true);
    }
    return Future.error(
        SyncError('The Document has been removed', status: 404, code: 54100));
  }

  @override
  void advanceLastEventId(int eventId, {String revision}) {
    // TODO: implement advanceLastEventId
  }
}
