import 'dart:async';

import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/errors/syncerror.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/core/router.dart';
import 'package:twilio_conversations/src/services/sync/removal_handler/removal_handler.dart';
import 'package:twilio_conversations/src/services/sync/structures/cache/cache.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/entity.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/live_query/models/insights_response_item.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/live_query/models/item.dart';

class LiveQueryImpl<Value> extends SyncEntity {
  LiveQueryImpl(
    RemovalHandler removalHandler, {
    List<InsightsQueryResponseItem<String, Value>> items,
    SyncNetwork network,
    SyncRouter router,
    Storage storage,
    String indexName,
    String sid,
    String queryExpression,
    String queryUri,
    int lastEventId,
    String insightsUri,
    Function liveQueryCreator,
  })  : _insightsUri = insightsUri,
        _indexName = indexName,
        _sid = sid,
        _queryExpression = queryExpression,
        _queryUri = queryUri,
        _lastEventId = lastEventId,
        super(removalHandler,
            network: network, storage: storage, router: router) {
    if (items != null) {
      items.forEach((item) {
        _cache.store(item.key, InsightsItem(key: item.key, value: item.data),
            item.revision);
      });
    }
  }

  final String _insightsUri;
  String _indexName;
  final String _sid;
  final String _queryExpression;
  String _queryUri;
  int _lastEventId;
  final Cache<String, InsightsItem<String, Value>> _cache =
      Cache<String, InsightsItem<String, Value>>();

  // public
  @override
  String get sid => _sid;

  // private extension of SyncEntity
  @override
  String get uniqueName => null;

  @override
  String get type => 'live_query';

  static String get staticType => 'live_query';

  @override
  int get lastEventId => _lastEventId;

  @override
  String get indexName => _indexName;

  @override
  String get queryString => _queryExpression;

  // custom private props
  String get queryUri => _queryUri;

  Map getItems() {
    final dataByString = {};
    _cache.forEach((key, item) {
      dataByString[key] = item;
    });
    return dataByString;
  }

  /// @private
  @override
  void update(Map<String, dynamic> message, {bool isStrictlyOrdered}) {
    switch (message['type']) {
      case 'live_query_item_updated':
        handleItemMutated(message['item_key'], message['item_data'],
            message['item_revision']);
        break;
      case 'live_query_item_removed':
        handleItemRemoved(message['item_key'], message['item_revision']);
        break;
      case 'live_query_updated':
        handleBatchUpdate(message['items']);
        break;
    }
    if (isStrictlyOrdered != null && isStrictlyOrdered) {
      advanceLastEventId(message['last_event_id']);
    }
  }

  void handleItemMutated(String key, Value value, int revision) {
    if (shouldIgnoreEvent(key, revision)) {
      //(`Item ${key} update skipped, revision: ${revision}`);
    } else {
      final InsightsItem item =
          InsightsItem<String, Value>(key: key, value: value);
      _cache.store(key, item, revision);
      broadcastEventToListeners('itemUpdated', item);
    }
  }

  void handleItemRemoved(String key, int revision) {
    final force = (revision == null);
    if (shouldIgnoreEvent(key, revision)) {
      // (`Item ${key} delete skipped, revision: ${revision}`);
    } else {
      _cache.delete(key, revision, force: force);
      broadcastEventToListeners('itemRemoved', key);
    }
  }

  void handleBatchUpdate(List<Map<String, dynamic>> items) {
    // preprocess item set for easy key-based access (it's a one-time constant time operation)
    final Map<String, InsightsQueryResponseItem> newItems = {};
    if (items != null) {
      items.forEach((item) {
        newItems[item['key']] = InsightsQueryResponseItem(
            data: item['data'], revision: int.tryParse(item['revision']));
      });
    }
    // go through existing items and generate update/remove events for them
    _cache.forEach((key, item) {
      final newItem = newItems[key];
      if (newItem != null) {
        handleItemMutated(key, newItem.data, newItem.revision);
      } else {
        handleItemRemoved(key, null); // force deletion w/o revision
      }
      // once item is handled, remove it from incoming array
      items.remove(key);
    });
    // once we handled all the known items, handle remaining pack
    for (var key in newItems.keys) {
      handleItemMutated(key, newItems[key].data, newItems[key].revision);
    }
  }

  bool shouldIgnoreEvent(String key, int eventId) {
    return key != null && eventId != null && _cache.isKnown(key, eventId);
  }

  /// @private
  @override
  void advanceLastEventId(int eventId, {String revision}) {
    // LiveQuery is not revisioned in any way, so simply ignore second param and act upon lastEventId only
    if (lastEventId < eventId) {
      _lastEventId = eventId;
    }
  }

  @override
  void onRemoved(bool locally) {}

  static Future<Map<String, dynamic>> queryItems(
      {SyncNetwork network,
      String queryString,
      String uri,
      String type}) async {
    if (queryString == null) {
      // should not be null or undefined
      throw SyncError('Invalid query', status: 400, code: 54507);
    }
    final liveQueryRequestBody = {
      'query_string': queryString
      // raw query string (like `key == "value" AND key2 != "value2"`)
    };
    if (type == 'live_query') {
      liveQueryRequestBody['type'] = type;
    }
    final response = await network.post(uri,
        body: liveQueryRequestBody, retryWhenThrottled: true);
    return response.data;
  }
}

/**
 * @class InsightsItem
 * @classdesc An individual result from a LiveQuery or InstantQuery result set.
 * @property {String} key The identifier that maps to this item within the search result.
 * @property {Object} value The contents of the item.
 */
/**
 * A result set, i.e. a collection of items that matched a LiveQuery or InstantQuery expression. Each result is a
 * key-value pair, where each key identifies its object uniquely. These results are equivalent to a set of
 * {@link InsightsItem}-s.
 * @typedef {Object.<string, Object>} LiveQuery#ItemsSnapshot
 */
/**
 * Fired when an item has been added or updated.
 * @event LiveQuery#itemUpdated
 * @param {InsightsItem} item Updated item.
 * @example
 * liveQuery.on('itemUpdated', function(item) {
 *   console.log('Item ' + item.key + ' was updated');
 *   console.log('Item value: ', item.value);
 * });
 */
/**
 * Fired when an existing item has been removed.
 * @event LiveQuery#itemRemoved
 * @param {Object} args Arguments provided with the event.
 * @param {String} args.key The key of the removed item.
 * @example
 * liveQuery.on('itemRemoved', function(args) {
 *   console.log('Item ' + args.key + ' was removed');
 * });
 */
/**
 * Fired when a search result is ready.
 * @event InstantQuery#searchResult
 * @param {LiveQuery#ItemsSnapshot} items A snapshot of items matching current query expression.
 * @example
 * instantQuery.on('searchResult', function(items) {
 *    Object.entries(items).forEach(([key, value]) => {
 *      console.log('Search result item key: ' + key);
 *      console.log('Search result item value: ' + value);
 *    });
 * });
 */
