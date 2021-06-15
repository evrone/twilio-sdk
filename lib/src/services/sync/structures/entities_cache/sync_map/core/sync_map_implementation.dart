import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/errors/syncerror.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/namespaced_merging/namespaced_merging_queue.dart';
import 'package:twilio_conversations/src/services/sync/core/router.dart';
import 'package:twilio_conversations/src/services/sync/removal_handler/removal_handler.dart';
import 'package:twilio_conversations/src/services/sync/structures/cache/cache.dart';
import 'package:twilio_conversations/src/utils/rest_paginator.dart';
import 'package:twilio_conversations/src/utils/sanitizer.dart';
import 'package:twilio_conversations/src/utils/sync_paginator.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

import '../../entity.dart';
import '../../models/entity_metadata.dart';
import '../models/map_item.dart';

class SyncMapImpl<T> extends SyncEntity {
  /// @private
  SyncMapImpl(RemovalHandler removalHandler,
      {SyncNetwork network,
      SyncRouter router,
      Storage storage,
      String dateExpires,
      DateTime dateUpdated,
      String revision,
      int lastEventId,
      Map<String, dynamic> links,
      String url,
      String sid,
      String uniqueName,
      List<MapItem> items})
      : _network = network,
        _storage = storage,
        _dateExpires = dateExpires,
        _dateUpdated = dateUpdated,
        _revision = revision,
        _lastEventId = lastEventId,
        _links = links,
        _url = url,
        _sid = sid,
        _uniqueName = uniqueName,
        super(removalHandler,
            router: router, network: network, storage: storage) {
    final updateRequestReducer = (acc, input) => (input.ttl is int)
        ? {
            ['ttl']: input.ttl
          }
        : acc;
    _updateMergingQueue = NamespacedMergingQueue(updateRequestReducer);

    if (items != null) {
      items.forEach((item) {
        _cache.store(item.key, item, item.lastEventId);
      });
    }
  }
  final SyncNetwork _network;

  final Storage _storage;
  final String _sid;
  final String _url;
  String _revision;
  int _lastEventId;
  final Map<String, dynamic> _links;
  final String _uniqueName;
  DateTime _dateUpdated;
  String _dateExpires;

  NamespacedMergingQueue _updateMergingQueue;
  final Cache<String, MapItem<T>> _cache = Cache<String, MapItem<T>>();
  // private props
  String get uri => _url;

  Map<String, dynamic> get links => _links;

  String get revision => _revision;

  @override
  int get lastEventId => _lastEventId;

  String get dateExpires => _dateExpires;

  static String get staticType => 'map';

  @override
  String get type => SyncMapImpl.staticType;

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

  DateTime get dateUpdated => _dateUpdated;

  Future set(String key, value, EntityMetadata itemMetadataUpdates) {
    final input = itemMetadataUpdates ?? EntityMetadata();
    validateOptionalTtl(input.ttl);
    return _updateMergingQueue.squashAndAdd(
        key, input, (input) => _putItemUnconditionally(key, value, input.ttl));
  }

  Future<MapItem<T>> get(String key) async {
    if (key == null) {
      throw SyncError('Item key may not be empty', status: 400, code: 54209);
    }
    if (_cache.has(key)) {
      return _cache.get(key);
    } else {
      return _getItemFromServer(key);
    }
  }

  Future<MapItem<T>> _getItemFromServer(String key) async {
    final result = await queryItems(key: key);
    if (result.items.isEmpty) {
      throw SyncError('The specified Map Item does not exist',
          status: 404, code: 54201);
    } else {
      return result.items.first;
    }
  }

  Future mutate(
      String key, Function mutator, EntityMetadata itemMetadataUpdates) {
    final input = itemMetadataUpdates ?? EntityMetadata();
    validateOptionalTtl(input.ttl);
    return _updateMergingQueue.add(
        key, input, (input) => _putItemWithIfMatch(key, mutator, input.ttl));
  }

  Future updateMetadata(String key, T data, itemMetadataUpdates) {
    return mutate(key, (remote) => remote.addAll(data), itemMetadataUpdates);
  }

  Future<MapItem<T>> _putItemUnconditionally(
      String key, T data, int ttl) async {
    final result = await _putItemToServer(key, data, null, ttl: ttl);
    final Map<String, dynamic> item = result['item'];
    _handleItemMutated(
        item['key'],
        item['url'],
        item['last_event_id'],
        item['revision'],
        item['data'],
        item['date_updated'],
        item['date_expires'],
        result['added'],
        false);
    return _cache.get(item['key']);
  }

  Future<MapItem<T>> _putItemWithIfMatch(
      String key, Function mutatorFunction, int ttl) async {
    var currentItem;
    try {
      currentItem = await get(key);
    } catch (error) {
      if (error.status == 404) {
        // PUT /Items/myKey with `If-Match: -1` acts as "put if not exists"
        return MapItem<T>(key: key, lastEventId: -1, revision: '-1');
      }
    }

    final data = mutatorFunction(currentItem.data);
    if (data != null) {
      final ifMatch = currentItem.revision;
      try {
        final result = await _putItemToServer(key, data, ifMatch, ttl: ttl);
        final item = result['item'];
        _handleItemMutated(
            item['key'],
            item['url'],
            item['last_event_id'],
            item['revision'],
            item['data'],
            item['date_updated'],
            item['date_expires'],
            result['added'],
            false);
        return _cache.get(item.key);
      } catch (error) {
        if (error.status == 412) {
          await _getItemFromServer(key);
          return _putItemWithIfMatch(key, mutatorFunction, ttl);
        }
      }
    } else {
      return currentItem;
    }
    return null;
  }

  Future<Map<String, dynamic>> _putItemToServer(
      String key, T data, String ifMatch,
      {int ttl}) async {
    final url = UriBuilder(links['items']).addPathSegment(key).build();
    final Map<String, dynamic> requestBody = {'data': data};
    if (ttl != null) {
      requestBody['ttl'] = ttl;
    }
    try {
      final response = await _network.put(url, requestBody, revision: ifMatch);
      final mapItemDescriptor = response.data;
      mapItemDescriptor.data =
          data; // The server does not return the data in the response
      final added = response.statusCode == 201;
      return {'added': added, 'item': mapItemDescriptor};
    } catch (error) {
      if (error.status == 404) {
        onRemoved(false);
      }
    }
    return {};
  }

  void remove(String key) async {
    final item = await get(key);
    final previousItemData = item.data;
    final response = await _network.delete(item.uri);
    _handleItemRemoved(key, response.data['last_event_id'], previousItemData,
        response.data['date_updated'], false);
  }

  /// @private
  Future<SyncPaginator<MapItem<T>>> queryItems(
      {String key,
      String from,
      int limit,
      int index,
      String pageToken,
      String order}) async {
    final uri = UriBuilder(links['items'])
        .addQueryParam('From', value: from)
        .addQueryParam('PageSize', value: limit)
        .addQueryParam('Key', value: key)
        .addQueryParam('PageToken', value: pageToken)
        .addQueryParam('Order', value: order)
        .build();
    final response = await _network.get(uri);
    final items = response.data.entries.map((el) {
      final itemInCache = _cache.get(el['key']);
      if (itemInCache != null) {
        _handleItemMutated(
            el['key'],
            el['url'],
            el['last_event_id'],
            el['revision'],
            el['data'],
            el['date_updated'],
            el['date_expires'],
            false,
            true);
      } else {
        _cache.store(
            el['key'],
            MapItem<T>(
              key: el['key'],
              url: el['url'],
              lastEventId: el['last_event_id'],
              revision: el['revision'],
              value: el['data'],
              dateUpdated: DateTime.tryParse(el['date_updated']),
              dateExpires: el['date_expires'],
            ),
            el['last_event_id']);
      }
      return _cache.get(el['key']);
    });
    final meta = response.data['meta'];
    return RestPaginator(
        items: items,
        source: (pageToken) => queryItems(pageToken: pageToken),
        prevToken: meta['previous_token'],
        nextToken: meta['next_token']);
  }

  Future<SyncPaginator<MapItem<T>>> getItems(
      {String key,
      String from,
      int limit,
      int index,
      String pageToken,
      String order = 'asc',
      int pageSize}) {
    validatePageSize(pageSize);
    final lim = pageSize ?? limit ?? 50;
    return queryItems(
        key: key,
        from: from,
        limit: lim,
        index: index,
        pageToken: pageToken,
        order: order);
  }

  bool shouldIgnoreEvent(String key, int eventId) {
    return _cache.isKnown(key, eventId);
  }

  /// Handle update from the server
  /// @private
  @override
  void update(Map<String, dynamic> update, {bool isStrictlyOrdered}) {
    switch (update['type']) {
      case 'map_item_added':
      case 'map_item_updated':
        {
          _handleItemMutated(
              update['item_key'],
              update['item_url'],
              update['id'],
              update['item_revision'],
              update['item_data'],
              DateTime.tryParse(update['date_created']),
              null, // orchestration events do not include date_expires
              update['type'] == 'map_item_added',
              true);
        }
        break;
      case 'map_item_removed':
        {
          _handleItemRemoved(
              update['item_key'],
              update['id'],
              update['item_data'],
              DateTime.tryParse(update['date_created']),
              true);
        }
        break;
      case 'map_removed':
        {
          onRemoved(false);
        }
        break;
    }
    if (isStrictlyOrdered) {
      advanceLastEventId(update['id'], revision: update['map_revision']);
    }
  }

  @override
  void advanceLastEventId(int eventId, {String revision}) {
    if (lastEventId < eventId) {
      _lastEventId = eventId;
      if (revision != null) {
        _revision = revision;
      }
    }
  }

  void _updateRootDateUpdated(DateTime dateUpdated) {
    if (_dateUpdated == null ||
        dateUpdated.millisecondsSinceEpoch >
            _dateUpdated.millisecondsSinceEpoch) {
      _dateUpdated = dateUpdated;
      _storage.update(type, sid,
          uniqueName: uniqueName, patch: {'dateUpdated': dateUpdated});
    }
  }

  void _handleItemMutated(
      String key,
      String url,
      int lastEventId,
      String revision,
      T data,
      DateTime dateUpdated,
      String dateExpires,
      bool added,
      bool remote) {
    if (shouldIgnoreEvent(key, lastEventId)) {
      // ('Item ', key, ' update skipped, current:', lastEventId, ', remote:', lastEventId);
      return;
    }
    _updateRootDateUpdated(dateUpdated);
    final item = _cache.get(key);
    if (item == null) {
      final newItem = MapItem<T>(
        key: key,
        url: url,
        lastEventId: lastEventId,
        revision: revision,
        value: data,
        dateUpdated: dateUpdated,
        dateExpires: dateExpires,
      );
      _cache.store(key, newItem, lastEventId);
      emitItemMutationEvent(newItem, remote, added);
      return;
    }
    final previousItemData = item.data;
    item.update(lastEventId, revision, data, dateUpdated);
    _cache.store(key, item, lastEventId);
    if (dateExpires != null) {
      item.updateDateExpires(dateExpires);
    }
    emitItemMutationEvent(item, remote, false,
        previousItemData: previousItemData);
  }

  void emitItemMutationEvent(MapItem<T> item, bool remote, bool added,
      {T previousItemData}) {
    final eventName = added ? 'itemAdded' : 'itemUpdated';
    final args = {'item': item, 'isLocal': !remote};
    if (!added) {
      args['previousItemData'] = previousItemData;
    }
    broadcastEventToListeners(eventName, args);
  }

  /// @private
  void _handleItemRemoved(
      String key, int eventId, T oldData, DateTime dateUpdated, bool remote) {
    _updateRootDateUpdated(dateUpdated);
    _cache.delete(key, eventId);
    broadcastEventToListeners('itemRemoved',
        {'key': key, 'isLocal': !remote, 'previousItemData': oldData});
  }

  @override
  void onRemoved(bool locally) {
    unsubscribe();
    removalHandler(type, sid, uniqueName);
    broadcastEventToListeners('removed', {'isLocal': locally});
  }

  void setTtl(int ttl) async {
    validateMandatoryTtl(ttl);
    try {
      final requestBody = {'ttl': ttl};
      final response = await _network.post(uri, body: requestBody);
      _dateExpires = response.data['dateExpires'];
    } catch (error) {
      if (error.status == 404) {
        onRemoved(false);
      }
    }
  }

  void setItemTtl(String key, int ttl) async {
    validateMandatoryTtl(ttl);
    final existingItem = await get(key);
    final requestBody = {'ttl': ttl};
    final response = await _network.post(existingItem.uri, body: requestBody);
    existingItem.updateDateExpires(response.data['date_expires']);
  }

  void removeMap() async {
    await _network.delete(uri);
    onRemoved(true);
  }
}
