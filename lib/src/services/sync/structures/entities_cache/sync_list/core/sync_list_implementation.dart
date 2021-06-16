import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/errors/syncerror.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/core/queue/namespaced_merging/namespaced_merging_queue.dart';
import 'package:twilio_conversations/src/services/sync/core/router.dart';
import 'package:twilio_conversations/src/services/sync/removal_handler/removal_handler.dart';
import 'package:twilio_conversations/src/services/sync/structures/cache/cache.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/models/entity_metadata.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_list/models/list_item.dart';
import 'package:twilio_conversations/src/utils/rest_paginator.dart';
import 'package:twilio_conversations/src/utils/sanitizer.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

import '../../entity.dart';

class ListDescriptor {
  ListDescriptor();
}

class SyncListImpl<T> extends SyncEntity {
  /// @private
  SyncListImpl(RemovalHandler removalHandler,
      {SyncNetwork network,
      SyncRouter router,
      Storage storage,
      String revision,
      String dateExpires,
      DateTime dateUpdated,
      String uniqueName,
      int lastEventId,
      String sid,
      String url,
      Map<String, dynamic> links})
      : _network = network,
        _storage = storage,
        _revision = revision,
        _dateExpires = dateExpires,
        _dateUpdated = dateUpdated,
        _uniqueName = uniqueName,
        _lastEventId = lastEventId,
        _sid = sid,
        _url = url,
        _links = links,
        super(removalHandler,
            network: network, router: router, storage: storage) {
    final updateRequestReducer =
        (acc, input) => (input.ttl is int) ? {'ttl': input.ttl} : acc;
    _updateMergingQueue = NamespacedMergingQueue(updateRequestReducer);
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
  final Cache<int, ListItem<T>> _cache = Cache<int, ListItem<T>>();
  Map<String, dynamic> context;
  int contextEventId;
  // private props
  String get uri => _url;

  String get revision => _revision;

  @override
  int get lastEventId => _lastEventId;

  dynamic get links => _links;

  String get dateExpires => _dateExpires;

  static String get staticType => 'list';

  @override
  String get type => SyncListImpl.staticType;

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

  Future<Map<String, dynamic>> _addOrUpdateItemOnServer(
      String url, T data, String ifMatch,
      {int ttl}) async {
    final Map<String, dynamic> requestBody = {'data': data};
    if (ttl != null) {
      requestBody['ttl'] = ttl;
    }
    final response =
        await _network.post(url, body: requestBody, revision: ifMatch);
    final responseMap = <String, dynamic>{};
    responseMap.addAll(response.data);
    responseMap['data'] = data;
    responseMap['date_updated'] =
        DateTime.tryParse(response.data['date_updated']);
    return responseMap;
  }

  Future<ListItem<T>> push(T value, {EntityMetadata itemMetadata}) async {
    final ttl = (itemMetadata ?? EntityMetadata()).ttl;
    validateOptionalTtl(ttl);
    final Map<String, dynamic> item =
        await _addOrUpdateItemOnServer(links.items, value, null, ttl: ttl);
    final index = item['index'];
    _handleItemMutated(
        index,
        item['url'],
        item['last_event_id'],
        item['revision'],
        value,
        item['date_updated'],
        item['date_expires'],
        true,
        false);
    return _cache.get(index);
  }

  Future set(int index, T value, EntityMetadata itemMetadataUpdates) {
    final input = itemMetadataUpdates ?? EntityMetadata();
    validateOptionalTtl(input.ttl);
    return _updateMergingQueue.squashAndAdd(index, input,
        (input) => _updateItemUnconditionally(index, value, input.ttl));
  }

  Future _updateItemUnconditionally(int index, T data, int ttl) async {
    final existingItem = await get(index);
    final Map<String, dynamic> itemDescriptor =
        await _addOrUpdateItemOnServer(existingItem.url, data, null, ttl: ttl);
    _handleItemMutated(
        index,
        itemDescriptor['url'],
        itemDescriptor['last_event_id'],
        itemDescriptor['revision'],
        itemDescriptor['data'],
        itemDescriptor['date_updated'],
        itemDescriptor['date_expires'],
        false,
        false);
    return _cache.get(index);
  }

  Future<ListItem<T>> _updateItemWithIfMatch(
      int index, Function mutatorFunction, int ttl) async {
    final existingItem = await get(index);
    final data = mutatorFunction(existingItem.value);
    if (data != null) {
      final ifMatch = existingItem.revision;
      try {
        final itemDescriptor = await _addOrUpdateItemOnServer(
            existingItem.url, data, ifMatch,
            ttl: ttl);
        _handleItemMutated(
            index,
            itemDescriptor['url'],
            itemDescriptor['last_event_id'],
            itemDescriptor['revision'],
            itemDescriptor['data'],
            itemDescriptor['date_updated'],
            itemDescriptor['date_expires'],
            false,
            false);
        return _cache.get(index);
      } catch (error) {
        if (error.status == 412) {
          await _getItemFromServer(index);
          return _updateItemWithIfMatch(index, mutatorFunction, ttl);
        }
      }
    }
    return existingItem;
  }

  Future<ListItem<T>> mutate(
      int index, Function mutator, EntityMetadata itemMetadataUpdates) {
    final input = itemMetadataUpdates ?? EntityMetadata();
    validateOptionalTtl(input.ttl);
    return _updateMergingQueue.add(index, input,
        (input) => _updateItemWithIfMatch(index, mutator, input.ttl));
  }

  Future<ListItem<T>> updateMetadata(int index, Map<String, dynamic> data,
      EntityMetadata itemMetadataUpdates) {
    return mutate(index, (remote) => remote.addAll(data), itemMetadataUpdates);
  }

  void remove(int index) async {
    final item = await get(index);
    final previousItemData = item.value;
    final response = await _network.delete(item.url);
    _handleItemRemoved(index, response.data['last_event_id'], previousItemData,
        response.data['date_updated'], false);
  }

  Future<ListItem<T>> get(int index) async {
    final cachedItem = _cache.get(index);
    if (cachedItem != null) {
      return cachedItem;
    } else {
      return await _getItemFromServer(index);
    }
  }

  Future<ListItem<T>> _getItemFromServer(int index) async {
    final result = await queryItems(index: index);
    if (result.items.isEmpty) {
      throw SyncError('No item with index $index found',
          status: 404, code: 54151);
    } else {
      return result.items.first;
    }
  }

  /// Query items from the List
  /// @private
  Future<RestPaginator<ListItem<T>>> queryItems(
      {int from = 0, int limit, int index, pageToken, String order}) async {
    final url = UriBuilder(links.items)
        .addQueryParam('From', value: from)
        .addQueryParam('PageSize', value: limit)
        .addQueryParam('Index', value: index)
        .addQueryParam('PageToken', value: pageToken)
        .addQueryParam('Order', value: order)
        .build();
    final response = await _network.get(url);
    final items = response.data['items'].map((el) {
      final itemInCache = _cache.get(el['index']);
      if (itemInCache != null) {
        _handleItemMutated(
            el['index'],
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
            el.index,
            ListItem(
              index: el['index'],
              url: el['url'],
              revision: el['revision'],
              lastEventId: el['last_event_id'],
              dateExpires: el['date_expires'],
              dateUpdated: el['date_updated'],
              value: el['data'],
            ),
            el['last_event_id']);
      }
      return _cache.get(el.index);
    });
    final meta = response.data['meta'];
    return RestPaginator<ListItem<T>>(
        items: items,
        source: (pageToken) => queryItems(pageToken: pageToken),
        prevToken: meta['previous_token'],
        nextToken: meta['next_token']);
  }

  Future<RestPaginator<ListItem<T>>> getItems(
      {int from,
      int pageSize,
      int limit,
      int index,
      String pageToken,
      String order}) {
    validatePageSize(pageSize);
    final lim = pageSize ?? limit ?? 50;
    final ord = order ?? 'asc';
    return queryItems(order: ord, limit: lim, from: from);
  }

  /// @return {Promise<Object>} Context of List
  /// @private
  Future<Map<String, dynamic>> getContext() async {
    if (context == null) {
      final response = await _network.get(links.context);
      // store fetched context if we have't received any newer update
      _updateContextIfRequired(
          response.data['data'], response.data['last_event_id']);
    }
    return context;
  }

  void setTtl(int ttl) async {
    validateMandatoryTtl(ttl);
    try {
      final requestBody = {'ttl': ttl};
      final response = await _network.post(uri, body: requestBody);
      _dateExpires = response.data['date_expires'];
    } catch (error) {
      if (error.status == 404) {
        onRemoved(false);
      }
    }
  }

  void setItemTtl(int index, int ttl) async {
    validateMandatoryTtl(ttl);
    final existingItem = await get(index);
    final requestBody = {'ttl': ttl};
    final response = await _network.post(existingItem.url, body: requestBody);
    existingItem.updateDateExpires(response.data['date_expires']);
  }

  void removeList() async {
    await _network.delete(uri);
    onRemoved(true);
  }

  @override
  void onRemoved(bool locally) {
    unsubscribe();
    removalHandler(type, sid, uniqueName);
    broadcastEventToListeners('removed', {'isLocal': locally});
  }

  bool shouldIgnoreEvent(int key, int eventId) {
    return _cache.isKnown(key, eventId);
  }

  /// Handle update, which came from the server.
  /// @private
  @override
  void update(Map<String, dynamic> update, {bool isStrictlyOrdered}) {
    final itemIndex = update['itemIndex'];
    //update.date_created = update.dateCreated; todo
    switch (update['type']) {
      case 'list_item_added':
      case 'list_item_updated':
        {
          _handleItemMutated(
              itemIndex,
              update['item_url'],
              update['id'],
              update['item_revision'],
              update['item_data'],
              DateTime.tryParse(update['date_created']),
              null, // orchestration does not include date_expires
              update['type'] == 'list_item_added',
              true);
        }
        break;
      case 'list_item_removed':
        {
          _handleItemRemoved(itemIndex, update['id'], update['item_data'],
              update['date_created'], true);
        }
        break;
      case 'list_context_updated':
        {
          _handleContextUpdate(
              update['context_data'], update['id'], update['date_created']);
        }
        break;
      case 'list_removed':
        {
          onRemoved(false);
        }
        break;
    }
    if (isStrictlyOrdered) {
      advanceLastEventId(update['id'], revision: update['listRevision']);
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
          uniqueName: uniqueName, patch: {'date_updated': dateUpdated});
    }
  }

  void _handleItemMutated(
      int index,
      String uri,
      int lastEventId,
      String revision,
      T data,
      DateTime dateUpdated,
      String dateExpires,
      bool added,
      bool remote) {
    if (shouldIgnoreEvent(index, lastEventId)) {
      // ('Item ', index, ' update skipped, current:', lastEventId, ', remote:', lastEventId);
      return;
    }
    _updateRootDateUpdated(dateUpdated);
    final item = _cache.get(index);
    if (item == null) {
      final newItem = ListItem<T>(
          index: index,
          url: uri,
          lastEventId: lastEventId,
          revision: revision,
          value: data,
          dateUpdated: dateUpdated,
          dateExpires: dateExpires);
      _cache.store(index, newItem, lastEventId);
      emitItemMutationEvent(newItem, remote, added);
      return;
    }
    final previousItemData = item.value;
    item.update(lastEventId, revision, data, dateUpdated);
    _cache.store(index, item, lastEventId);
    if (dateExpires != null) {
      item.updateDateExpires(dateExpires);
    }
    emitItemMutationEvent(item, remote, false,
        previousItemData: previousItemData);
  }

  /// @private
  void emitItemMutationEvent(ListItem<T> item, bool remote, bool added,
      {previousItemData}) {
    final eventName = added ? 'itemAdded' : 'itemUpdated';
    final args = {'item': item, 'isLocal': !remote};
    if (added == null) {
      args['previousItemData'] = previousItemData;
    }
    broadcastEventToListeners(eventName, args);
  }

  /// @private
  void _handleItemRemoved(
      int index, int eventId, T oldData, DateTime dateUpdated, bool remote) {
    _updateRootDateUpdated(dateUpdated);
    _cache.delete(index, eventId);
    broadcastEventToListeners('itemRemoved',
        {'index': index, 'isLocal': !remote, 'previousItemData': oldData});
  }

  /// @private
  void _handleContextUpdate(
      Map<String, dynamic> data, int eventId, DateTime dateUpdated) {
    _updateRootDateUpdated(dateUpdated);
    if (_updateContextIfRequired(data, eventId)) {
      broadcastEventToListeners(
          'contextUpdated', {'context': data, 'isLocal': false});
    }
  }

  /// @private
  bool _updateContextIfRequired(Map<String, dynamic> data, int eventId) {
    if (contextEventId == null || eventId > contextEventId) {
      context = data;
      contextEventId = eventId;
      return true;
    } else {
      // ('Context update skipped, current:', lastEventId, ', remote:', eventId);
      return false;
    }
  }
}
