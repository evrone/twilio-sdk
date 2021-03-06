import 'package:twilio_conversations/src/services/sync/core/closable.dart';
import 'package:twilio_conversations/src/utils/rest_paginator.dart';

import '../models/entity_metadata.dart';
import 'core/sync_list_implementation.dart';
import 'models/list_item.dart';

export 'extensions/sync_list_pagination.dart';

/// @class
/// @alias List
/// @classdesc Represents a Sync List, which stores an ordered list of values.
/// Use the {@link Client#list} method to obtain a reference to a Sync List.
/// Information about rate limits can be found {@link https://www.twilio.com/docs/sync/limits|here}.
/// @property {String} sid - List unique id, immutable identifier assigned by the system.
/// @property {String} [uniqueName=null] - List unique name, immutable identifier that can be assigned to list during creation.
/// @property {Date} dateUpdated Date when the List was last updated, given in UTC ISO 8601 format (e.g., '2018-04-26T15:23:19.732Z')
///
/// @fires List#removed
/// @fires List#itemAdded
/// @fires List#itemRemoved
/// @fires List#itemUpdated
class SyncList<T> extends Closeable {
  SyncList(this._syncListImpl) : super() {
    _syncListImpl.attach(this);
  }

  final SyncListImpl<T> _syncListImpl;
// private props
  String get uri => _syncListImpl.uri;

  String get revision => _syncListImpl.revision;

  int get lastEventId => _syncListImpl.lastEventId;

  Map<String, dynamic> get links => _syncListImpl.links;

  String get dateExpires => _syncListImpl.dateExpires;

  static String get staticType => SyncListImpl.staticType;

  String get type => SyncListImpl.staticType;

// public props, documented along with class description
  String get sid => _syncListImpl.sid;

  String get uniqueName => _syncListImpl.uniqueName;

  DateTime get dateUpdated => _syncListImpl.dateUpdated;

  /// Add a new item to the list.
  /// @param {Object} data Data to be added.
  /// @param {List#EntityMetadata} [itemMetadata] Item metadata.
  /// @returns {Promise<ListItem>} A newly added item.
  /// @public
  /// @example
  /// list.push({ name: 'John Smith' }, { ttl: 86400 })
  ///   .then(function(item) {
  ///     console.log('List Item push() successful, item index: ' + item.index + ', data: ', item.data)
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List Item push() failed', error);
  ///   });
  Future<ListItem<T>> push(T data, {EntityMetadata itemMetadata}) {
    ensureNotClosed();
    return _syncListImpl.push(data, itemMetadata: itemMetadata);
  }

  /// Assign new data to an existing item, given its index.
  /// @param {Number} index Index of the item to be updated.
  /// @param {Object} value New data to be assigned to an item.
  /// @param {List#EntityMetadata} [itemMetadataUpdates] New item metadata.
  /// @returns {Promise<ListItem>} A promise with updated item containing latest known data.
  /// The promise will be rejected if the item does not exist.
  /// @public
  /// @example
  /// list.set(42, { name: 'John Smith' }, { ttl: 86400 })
  ///   .then(function(item) {
  ///     console.log('List Item set() successful, item data:', item.data)
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List Item set() failed', error);
  ///   });
  Future<ListItem<T>> set(
      int index, T value, EntityMetadata itemMetadataUpdates) {
    ensureNotClosed();
    return _syncListImpl.set(index, value, itemMetadataUpdates);
  }

  /// Modify an existing item by applying a mutation function to it.
  /// @param {Number} index Index of an item to be changed.
  /// @param {List~Mutator} mutator A function that outputs a new data based on the existing data.
  /// @param {List#EntityMetadata} [itemMetadataUpdates] New item metadata.
  /// @returns {Promise<ListItem>} Resolves with the most recent item state, the output of a successful
  ///    mutation or a state that prompted graceful cancellation (mutator returned <code>null</code>). This promise
  ///    will be rejected if the indicated item does not already exist.
  /// @public
  /// @example
  /// var mutatorFunction = function(currentValue) {
  ///     currentValue.viewCount = (currentValue.viewCount || 0) + 1;
  ///     return currentValue;
  /// };
  /// list.mutate(42, mutatorFunction, { ttl: 86400 })
  ///   .then(function(item) {
  ///     console.log('List Item mutate() successful, new data:', item.data)
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List Item mutate() failed', error);
  ///   });
  Future<ListItem<T>> mutate(
      int index, Function mutator, EntityMetadata itemMetadataUpdates) {
    ensureNotClosed();
    return _syncListImpl.mutate(index, mutator, itemMetadataUpdates);
  }

  /// Modify an existing item by appending new fields (or overwriting existing ones) with the values from Object.
  /// This is equivalent to
  /// <pre>
  /// list.mutate(42, function(currentValue) {
  ///   return Object.assign(currentValue, obj));
  /// });
  /// </pre>
  /// @param {Number} index Index of an item to be changed.
  /// @param {Object} obj Set of fields to update.
  /// @param {List#EntityMetadata} [itemMetadataUpdates] New item metadata.
  /// @returns {Promise<ListItem>} A promise with a modified item containing latest known data.
  /// The promise will be rejected if an item was not found.
  /// @public
  /// @example
  /// // Say, the List Item (index: 42) data is { name: 'John Smith' }
  /// list.update(42, { age: 34 }, { ttl: 86400 })
  ///   .then(function(item) {
  ///     // Now the List Item data is { name: 'John Smith', age: 34 }
  ///     console.log('List Item update() successful, new data:', item.data);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List Item update() failed', error);
  ///   });
  Future<ListItem<T>> update(int index, Map<String, dynamic> json,
      EntityMetadata itemMetadataUpdates) {
    ensureNotClosed();
    return _syncListImpl.updateMetadata(index, json, itemMetadataUpdates);
  }

  /// Delete an item, given its index.
  /// @param {Number} index Index of an item to be removed.
  /// @returns {Promise<void>} A promise to remove an item.
  /// A promise will be rejected if an item was not found.
  /// @public
  /// @example
  /// list.remove(42)
  ///   .then(function() {
  ///     console.log('List Item remove() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List Item remove() failed', error);
  ///   });
  void remove(int index) {
    ensureNotClosed();
    _syncListImpl.remove(index);
  }

  /// Retrieve an item by List index.
  /// @param {Number} index Item index in a List.
  /// @returns {Promise<ListItem>} A promise with an item containing latest known data.
  /// A promise will be rejected if an item was not found.
  /// @public
  /// @example
  /// list.get(42)
  ///   .then(function(item) {
  ///     console.log('List Item get() successful, item data:', item.data)
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List Item get() failed', error);
  ///   });
  Future<ListItem<T>> get(index) {
    ensureNotClosed();
    return _syncListImpl.get(index);
  }

  /// Retrieve a List context
  /// @returns {Promise<Object>} A promise with a List's context
  /// @ignore
  Future<Map<String, dynamic>> getContext() {
    ensureNotClosed();
    return _syncListImpl.getContext();
  }

  /// Query a list of items from collection.
  /// Information about the query limits can be found {@link https://www.twilio.com/docs/sync/limits|here}.
  /// @param {Object} [queryOptions] Arguments for query
  /// @param {Number} [queryOptions.from] Item index, which should be used as the offset.
  /// If undefined, starts from the beginning or end depending on queryOptions.order.
  /// @param {Number} [queryOptions.pageSize=50] Results page size.
  /// @param {'asc'|'desc'} [queryOptions.order='asc'] Numeric order of results.
  /// @returns {Promise<Paginator<ListItem>>}
  /// @public
  /// @example
  /// var pageHandler = function(paginator) {
  ///   paginator.items.forEach(function(item) {
  ///     console.log('Item ' + item.index + ': ', item.data);
  ///   });
  ///   return paginator.hasNextPage ? paginator.nextPage().then(pageHandler)
  ///                                : null;
  /// };
  /// list.getItems({ from: 0, order: 'asc' })
  ///   .then(pageHandler)
  ///   .catch(function(error) {
  ///     console.error('List getItems() failed', error);
  ///   });
  Future<RestPaginator<ListItem<T>>> getItems(
      {from = 0, pageSize = 50, order = 'asc'}) async {
    ensureNotClosed();
    return await _syncListImpl.getItems(
        pageSize: pageSize, order: order, from: from);
  }

  /// Update the time-to-live of the list.
  /// @param {Number} ttl Specifies the TTL in seconds after which the list is subject to automatic deletion. The value 0 means infinity.
  /// @return {Promise<void>} A promise that resolves after the TTL update was successful.
  /// @public
  /// @example
  /// list.setTtl(3600)
  ///   .then(function() {
  ///     console.log('List setTtl() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List setTtl() failed', error);
  ///   });
  void setTtl(int ttl) {
    ensureNotClosed();
    _syncListImpl.setTtl(ttl);
  }

  /// Update the time-to-live of a list item.
  /// @param {Number} index Item index.
  /// @param {Number} ttl Specifies the TTL in seconds after which the list item is subject to automatic deletion. The value 0 means infinity.
  /// @return {Promise<void>} A promise that resolves after the TTL update was successful.
  /// @public
  /// @example
  /// list.setItemTtl(42, 86400)
  ///   .then(function() {
  ///     console.log('List setItemTtl() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List setItemTtl() failed', error);
  ///   });
  void setItemTtl(int index, int ttl) {
    ensureNotClosed();
    _syncListImpl.setItemTtl(index, ttl);
  }

  /// Delete this list. It will be impossible to restore it.
  /// @return {Promise<void>} A promise that resolves when the list has been deleted.
  /// @public
  /// @example
  /// list.removeList()
  ///   .then(function() {
  ///     console.log('List removeList() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('List removeList() failed', error);
  ///   });
  void removeList() {
    ensureNotClosed();
    removeList();
  }

  /// Conclude work with the list instance and remove all event listeners attached to it.
  /// Any subsequent operation on this object will be rejected with error.
  /// Other local copies of this list will continue operating and receiving events normally.
  /// @public
  /// @example
  /// list.close();
  @override
  void close() {
    super.close();
    _syncListImpl.detach(listenerUuid);
  }
}

//
// Contains List Item metadata.
// @typedef {Object} List#EntityMetadata
// @property {Number} [ttl] Specifies the time-to-live in seconds after which the list item is subject to automatic deletion.
// The value 0 means infinity.
//
//
// Applies a transformation to the item data. May be called multiple times on the
// same datum in case of collisions with remote code.
// @callback List~Mutator
// @param {Object} currentValue The current data of the item in the cloud.
// @return {Object} The desired new data for the item or <code>null</code> to gracefully cancel the mutation.
//
//
// Fired when a new item appears in the list, whether its creator was local or remote.
// @event List#itemAdded
// @param {Object} args Arguments provided with the event.
// @param {ListItem} args.item Added item.
// @param {Boolean} args.isLocal Equals 'true' if item was added by local actor, 'false' otherwise.
// @example
// list.on('itemAdded', function(args) {
//   console.log('List item ' + args.item.index + ' was added');
//   console.log('args.item.data:', args.item.data);
//   console.log('args.isLocal:', args.isLocal);
// });
//
//
// Fired when a list item is updated (not added or removed, but changed), whether the updater was local or remote.
// @event List#itemUpdated
// @param {Object} args Arguments provided with the event.
// @param {ListItem} args.item Updated item.
// @param {Boolean} args.isLocal Equals 'true' if item was updated by local actor, 'false' otherwise.
// @param {Object} args.previousItemData Contains a snapshot of the item data before the update.
// @example
// list.on('itemUpdated', function(args) {
//   console.log('List item ' + args.item.index + ' was updated');
//   console.log('args.item.data:', args.item.data);
//   console.log('args.isLocal:', args.isLocal);
//   console.log('args.previousItemData:', args.previousItemData);
// });
//
//
// Fired when a list item is removed, whether the remover was local or remote.
// @event List#itemRemoved
// @param {Object} args Arguments provided with the event.
// @param {Number} args.index The index of the removed item.
// @param {Boolean} args.isLocal Equals 'true' if item was removed by local actor, 'false' otherwise.
// @param {Object} args.previousItemData Contains a snapshot of item data before removal.
// @example
// list.on('itemRemoved', function(args) {
//   console.log('List item ' + args.index + ' was removed');
//   console.log('args.previousItemData:', args.previousItemData);
//   console.log('args.isLocal:', args.isLocal);
// });
//
//
// Fired when a list is deleted entirely, by any actor local or remote.
// @event List#removed
// @param {Object} args Arguments provided with the event.
// @param {Boolean} args.isLocal Equals 'true' if list was removed by local actor, 'false' otherwise.
// @example
// list.on('removed', function(args) {
//   console.log('List ' + list.sid + ' was removed');
//   console.log('args.isLocal:', args.isLocal);
// });
//
