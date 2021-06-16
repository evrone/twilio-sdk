import 'package:twilio_conversations/src/services/sync/core/closable.dart';
import 'package:twilio_conversations/src/utils/rest_paginator.dart';

import '../models/entity_metadata.dart';
import 'core/sync_map_implementation.dart';
import 'models/map_item.dart';

/// @class
/// @alias Map
/// @classdesc Represents a Sync Map, which stores an unordered set of key:value pairs.
/// Use the {@link Client#map} method to obtain a reference to a Sync Map.
/// Information about rate limits can be found {@link https://www.twilio.com/docs/sync/limits|here}.
/// @property {String} sid An immutable identifier (a SID) assigned by the system on creation.
/// @property {String} [uniqueName=null] - An optional immutable identifier that may be assigned by the
/// programmer to this map on creation. Unique among other Maps.
/// @property {Date} dateUpdated Date when the Map was last updated.
///
/// @fires Map#removed
/// @fires Map#itemAdded
/// @fires Map#itemRemoved
/// @fires Map#itemUpdated
class SyncMap<T> extends Closeable {
  SyncMap(this._syncMapImpl) : super() {
    _syncMapImpl.attach(this);
  }
  final SyncMapImpl<T> _syncMapImpl;
  // private props
  String get uri => _syncMapImpl.uri;

  Map<String, dynamic> get links => _syncMapImpl.links;

  String get revision => _syncMapImpl.revision;

  int get lastEventId => _syncMapImpl.lastEventId;

  String get dateExpires => _syncMapImpl.dateExpires;

  static String get staticType => SyncMapImpl.staticType;

  String get type => SyncMapImpl.staticType;

  // public props, documented along with class description
  String get sid => _syncMapImpl.sid;

  String get uniqueName => _syncMapImpl.uniqueName;

  DateTime get dateUpdated => _syncMapImpl.dateUpdated;

  /// Add a new item to the map with the given key:value pair. Overwrites any data that might already exist at that key.
  /// @param {String} key Unique item identifier.
  /// @param {Object} data Data to be set.
  /// @param {Map#EntityMetadata} [itemMetadataUpdates] New item metadata.
  /// @returns {Promise<MapItem>} Newly added item, or modified one if already exists, with the latest known data.
  /// @public
  /// @example
  /// map.set('myKey', { name: 'John Smith' }, { ttl: 86400 })
  ///   .then(function(item) {
  ///     console.log('Map Item set() successful, item data:', item.data);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map Item set() failed', error);
  ///   });
  Future<MapItem<T>> set(String key, Map<String, dynamic> json,
      EntityMetadata itemMetadataUpdates) {
    ensureNotClosed();
    return _syncMapImpl.set(key, json, itemMetadataUpdates);
  }

  /// Retrieve an item by key.
  /// @param {String} key Identifies the desired item.
  /// @returns {Promise<MapItem>} A promise that resolves when the item has been fetched.
  /// This promise will be rejected if item was not found.
  /// @public
  /// @example
  /// map.get('myKey')
  ///   .then(function(item) {
  ///     console.log('Map Item get() successful, item data:', item.data)
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map Item get() failed', error);
  ///   });
  Future<MapItem<T>> get(String key) {
    ensureNotClosed();
    return _syncMapImpl.get(key);
  }

  /// Schedules a modification to this Map Item that will apply a mutation function.
  /// If no Item with the given key exists, it will first be created, having the default data (<code>{}</code>).
  /// @param {String} key Selects the map item to be mutated.
  /// @param {Map~Mutator} mutator A function that outputs a new data based on the existing data.
  /// May be called multiple times, particularly if this Map Item is modified concurrently by remote code.
  /// If the mutation ultimately succeeds, the Map Item will have made the particular transition described
  /// by this function.
  /// @param {Map#EntityMetadata} [itemMetadataUpdates] New item metadata.
  /// @returns {Promise<MapItem>} Resolves with the most recent item state, the output of a successful
  /// mutation or a state that prompted graceful cancellation (mutator returned <code>null</code>).
  /// @public
  /// @example
  /// var mutatorFunction = function(currentData) {
  ///     currentData.viewCount = (currentData.viewCount || 0) + 1;
  ///     return currentData;
  /// };
  /// map.mutate('myKey', mutatorFunction, { ttl: 86400 })
  ///   .then(function(item) {
  ///     console.log('Map Item mutate() successful, new data:', item.data)
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map Item mutate() failed', error);
  ///   });
  Future<MapItem<T>> mutate(
      String key, Function mutator, EntityMetadata itemMetadataUpdates) {
    ensureNotClosed();
    return _syncMapImpl.mutate(key, mutator, itemMetadataUpdates);
  }

  /// Modify a map item by appending new fields (or by overwriting existing ones) with the values from
  /// the provided Object. Creates a new item if no item by this key exists, copying all given fields and values
  /// into it.
  /// This is equivalent to
  /// <pre>
  /// map.mutate('myKey', function(currentData) {
  ///   return Object.assign(currentData, obj));
  /// });
  /// </pre>
  /// @param {String} key Selects the map item to update.
  /// @param {Object} obj Specifies the particular (top-level) attributes that will receive new values.
  /// @param {Map#EntityMetadata} [itemMetadataUpdates] New item metadata.
  /// @returns {Promise<MapItem>} A promise resolving to the modified item in its new state.
  /// @public
  /// @example
  /// // Say, the Map Item (key: 'myKey') data is { name: 'John Smith' }
  /// map.update('myKey', { age: 34 }, { ttl: 86400 })
  ///   .then(function(item) {
  ///     // Now the Map Item data is { name: 'John Smith', age: 34 }
  ///     console.log('Map Item update() successful, new data:', item.data);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map Item update() failed', error);
  ///   });
  Future<MapItem<T>> updateMetadata(
      String key, T data, EntityMetadata itemMetadataUpdates) {
    ensureNotClosed();
    return _syncMapImpl.updateMetadata(key, data, itemMetadataUpdates);
  }

  /// Delete an item, given its key.
  /// @param {String} key Selects the item to delete.
  /// @returns {Promise<void>} A promise to remove an item.
  /// The promise will be rejected if 'key' is undefined or an item was not found.
  /// @public
  /// @example
  /// map.remove('myKey')
  ///   .then(function() {
  ///     console.log('Map Item remove() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map Item remove() failed', error);
  ///   });
  void remove(String key) {
    ensureNotClosed();
    _syncMapImpl.remove(key);
  }

  /// Get a complete list of items from the map.
  /// Information about the query limits can be found {@link https://www.twilio.com/docs/sync/limits|here}.
  /// @param {Object} [queryOptions] Arguments for query.
  /// @param {String} [queryOptions.from] Item key, which should be used as the offset. If undefined, starts from the beginning or end depending on
  /// queryOptions.order.
  /// @param {Number} [queryOptions.pageSize=50] Result page size.
  /// @param {'asc'|'desc'} [queryOptions.order='asc'] Lexicographical order of results.
  /// @return {Promise<Paginator<MapItem>>}
  /// @public
  /// @example
  /// var pageHandler = function(paginator) {
  ///   paginator.items.forEach(function(item) {
  ///     console.log('Item ' + item.key + ': ', item.data);
  ///   });
  ///   return paginator.hasNextPage ? paginator.nextPage().then(pageHandler)
  ///                                : null;
  /// };
  /// map.getItems({ from: 'myKey', order: 'asc' })
  ///   .then(pageHandler)
  ///   .catch(function(error) {
  ///     console.error('Map getItems() failed', error);
  ///   });
  Future<RestPaginator<MapItem<T>>> getItems(
      {String key, String from, int pageSize = 50, String order = 'asc'}) {
    ensureNotClosed();
    return _syncMapImpl.getItems(
        key: key, from: from, pageSize: pageSize, order: order);
  }

  /// Update the time-to-live of the map.
  /// @param {Number} ttl Specifies the TTL in seconds after which the map is subject to automatic deletion. The value 0 means infinity.
  /// @return {Promise<void>} A promise that resolves after the TTL update was successful.
  /// @public
  /// @example
  /// map.setTtl(3600)
  ///   .then(function() {
  ///     console.log('Map setTtl() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map setTtl() failed', error);
  ///   });
  void setTtl(int ttl) {
    ensureNotClosed();
    return _syncMapImpl.setTtl(ttl);
  }

  /// Update the time-to-live of a map item.
  /// @param {Number} key Item key.
  /// @param {Number} ttl Specifies the TTL in seconds after which the map item is subject to automatic deletion. The value 0 means infinity.
  /// @return {Promise<void>} A promise that resolves after the TTL update was successful.
  /// @public
  /// @example
  /// map.setItemTtl('myKey', 86400)
  ///   .then(function() {
  ///     console.log('Map setItemTtl() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map setItemTtl() failed', error);
  ///   });
  void setItemTtl(String key, int ttl) {
    ensureNotClosed();
    return _syncMapImpl.setItemTtl(key, ttl);
  }

  /// Delete this map. It will be impossible to restore it.
  /// @return {Promise<void>} A promise that resolves when the map has been deleted.
  /// @public
  /// @example
  /// map.removeMap()
  ///   .then(function() {
  ///     console.log('Map removeMap() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Map removeMap() failed', error);
  ///   });
  void removeMap() {
    ensureNotClosed();
    _syncMapImpl.removeMap();
  }

  /// Conclude work with the map instance and remove all event listeners attached to it.
  /// Any subsequent operation on this object will be rejected with error.
  /// Other local copies of this map will continue operating and receiving events normally.
  /// @public
  /// @example
  /// map.close();
  @override
  void close() {
    super.close();
    _syncMapImpl.detach(listenerUuid);
  }
}

//
// Contains Map Item metadata.
// @typedef {Object} Map#EntityMetadata
// @property {Number} [ttl] Specifies the time-to-live in seconds after which the map item is subject to automatic deletion.
// The value 0 means infinity.
//
//
// Applies a transformation to the item data. May be called multiple times on the
// same datum in case of collisions with remote code.
// @callback Map~Mutator
// @param {Object} currentData The current data of the item in the cloud.
// @return {Object} The desired new data for the item or <code>null</code> to gracefully cancel the mutation.
//
//
// Fired when a new item appears in the map, whether its creator was local or remote.
// @event Map#itemAdded
// @param {Object} args Arguments provided with the event.
// @param {MapItem} args.item Added item.
// @param {Boolean} args.isLocal Equals 'true' if item was added by local actor, 'false' otherwise.
// @example
// map.on('itemAdded', function(args) {
//   console.log('Map item ' + args.item.key + ' was added');
//   console.log('args.item.data:', args.item.data);
//   console.log('args.isLocal:', args.isLocal);
// });
//
//
// Fired when a map item is updated (not added or removed, but changed), whether the updater was local or remote.
// @event Map#itemUpdated
// @param {Object} args Arguments provided with the event.
// @param {MapItem} args.item Updated item.
// @param {Boolean} args.isLocal Equals 'true' if item was updated by local actor, 'false' otherwise.
// @param {Object} args.previousItemData Contains a snapshot of the item data before the update.
// @example
// map.on('itemUpdated', function(args) {
//   console.log('Map item ' + args.item.key + ' was updated');
//   console.log('args.item.data:', args.item.data);
//   console.log('args.isLocal:', args.isLocal);
//   console.log('args.previousItemData:', args.previousItemData);
// });
//
//
// Fired when a map item is removed, whether the remover was local or remote.
// @event Map#itemRemoved
// @param {Object} args Arguments provided with the event.
// @param {String} args.key The key of the removed item.
// @param {Boolean} args.isLocal Equals 'true' if item was removed by local actor, 'false' otherwise.
// @param {Object} args.previousItemData Contains a snapshot of item data before removal.
// @example
// map.on('itemRemoved', function(args) {
//   console.log('Map item ' + args.key + ' was removed');
//   console.log('args.previousItemData:', args.previousItemData);
//   console.log('args.isLocal:', args.isLocal);
// });
//
//
// Fired when a map is deleted entirely, by any actor local or remote.
// @event Map#removed
// @param {Object} args Arguments provided with the event.
// @param {Boolean} args.isLocal Equals 'true' if map was removed by local actor, 'false' otherwise.
// @example
// map.on('removed', function(args) {
//   console.log('Map ' + map.sid + ' was removed');
//   console.log('args.isLocal:', args.isLocal);
// });
//
