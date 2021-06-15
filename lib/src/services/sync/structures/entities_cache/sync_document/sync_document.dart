import 'package:twilio_conversations/src/services/sync/core/closable.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/models/entity_metadata.dart';

import 'core/sync_document_implementation.dart';

/// @class
/// @alias Document
/// @classdesc Represents a Sync Document, the contents of which is a single JSON object.
/// Use the {@link Client#document} method to obtain a reference to a Sync Document.
/// Information about rate limits can be found {@link https://www.twilio.com/docs/sync/limits|here}.
/// @property {String} sid The immutable identifier of this document, assigned by the system.
/// @property {String} [uniqueName=null] An optional immutable identifier that may be assigned by the programmer
/// to this document during creation. Globally unique among other Documents.
/// @property {Date} dateUpdated Date when the Document was last updated.
/// @property {Object} data The contents of this document.
///
/// @fires Document#removed
/// @fires Document#updated
class SyncDocument extends Closeable {
  SyncDocument(this.syncDocumentImpl) : super() {
    syncDocumentImpl.attach(this);
  }
  final SyncDocumentImpl syncDocumentImpl;
// private props
  String get uri => syncDocumentImpl.uri;

  String get revision => syncDocumentImpl.revision;

  int get lastEventId => syncDocumentImpl.lastEventId;

  String get dateExpires => syncDocumentImpl.dateExpires;

  static String get staticType => SyncDocumentImpl.staticType;
  String get type => syncDocumentImpl.type;

// public props, documented along with class description
  String get sid => syncDocumentImpl.sid;

  Map<String, dynamic> get data => syncDocumentImpl.data;

  DateTime get dateUpdated => syncDocumentImpl.dateUpdated;

  String get uniqueName => syncDocumentImpl.uniqueName;

  /// Assign new contents to this document. The current data will be overwritten.
  /// @param {Object} data The new contents to assign.
  /// @param {Document#Metadata} [metadataUpdates] New document metadata.
  /// @returns {Promise<Object>} A promise resolving to the new data of the document.
  /// @public
  /// @example
  /// // Say, the Document data is { name: 'John Smith', age: 34 }
  /// document.set({ name: 'Barbara Oaks' }, { ttl: 86400 })
  ///   .then(function(newValue) {
  ///     // Now the Document data is { name: 'Barbara Oaks' }
  ///     console.log('Document set() successful, new data:', newValue);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Document set() failed', error);
  ///   });
  Future set(Map<String, dynamic> data, EntityMetadata metadataUpdates) async {
    ensureNotClosed();
    return await syncDocumentImpl.set(data, metadataUpdates);
  }

  /// Schedules a modification to this document that will apply a mutation function.
  /// @param {Document~Mutator} mutator A function that outputs a new data based on the existing data.
  /// May be called multiple times, particularly if this Document is modified concurrently by remote code.
  /// If the mutation ultimately succeeds, the Document will have made the particular transition described
  /// by this function.
  /// @param {Document#Metadata} [metadataUpdates] New document metadata.
  /// @return {Promise<Object>} Resolves with the most recent Document state, whether the output of a
  ///    successful mutation or a state that prompted graceful cancellation (mutator returned <code>null</code>).
  /// @public
  /// @example
  /// var mutatorFunction = function(currentValue) {
  ///     currentValue.viewCount = (currentValue.viewCount || 0) + 1;
  ///     return currentValue;
  /// };
  /// document.mutate(mutatorFunction, { ttl: 86400 }))
  ///   .then(function(newValue) {
  ///     console.log('Document mutate() successful, new data:', newValue);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Document mutate() failed', error);
  ///   });
  Future mutate(Function mutator, EntityMetadata metadataUpdates) {
    ensureNotClosed();
    return syncDocumentImpl.mutate(mutator, metadataUpdates);
  }

  /// Modify a document by appending new fields (or by overwriting existing ones) with the values from the provided Object.
  /// This is equivalent to
  /// <pre>
  /// document.mutate(function(currentValue) {
  ///   return Object.assign(currentValue, obj));
  /// });
  /// </pre>
  /// @param {Object} obj Specifies the particular (top-level) attributes that will receive new values.
  /// @param {Document#Metadata} [metadataUpdates] New document metadata.
  /// @return {Promise<Object>} A promise resolving to the new data of the document.
  /// @public
  /// @example
  /// // Say, the Document data is { name: 'John Smith' }
  /// document.update({ age: 34 }, { ttl: 86400 })
  ///   .then(function(newValue) {
  ///     // Now the Document data is { name: 'John Smith', age: 34 }
  ///     console.log('Document update() successful, new data:', newValue);
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Document update() failed', error);
  ///   });
  Future update(Map<String, dynamic> json, EntityMetadata metadataUpdates) {
    ensureNotClosed();
    return syncDocumentImpl.updateMetadata(json, metadataUpdates);
  }

  /// Update the time-to-live of the document.
  /// @param {Number} ttl Specifies the time-to-live in seconds after which the document is subject to automatic deletion. The value 0 means infinity.
  /// @return {Promise<void>} A promise that resolves after the TTL update was successful.
  /// @public
  /// @example
  /// document.setTtl(3600)
  ///   .then(function() {
  ///     console.log('Document setTtl() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Document setTtl() failed', error);
  ///   });
  void setTtl(int ttl) {
    ensureNotClosed();
    syncDocumentImpl.setTtl(ttl);
  }

  /// Delete a document.
  /// @return {Promise<void>} A promise which resolves if (and only if) the document is ultimately deleted.
  /// @public
  /// @example
  /// document.removeDocument()
  ///   .then(function() {
  ///     console.log('Document removeDocument() successful');
  ///   })
  ///   .catch(function(error) {
  ///     console.error('Document removeDocument() failed', error);
  ///   });
  Future<void> removeDocument() async {
    ensureNotClosed();
    return syncDocumentImpl.removeDocument();
  }

  /// Conclude work with the document instance and remove all event listeners attached to it.
  /// Any subsequent operation on this object will be rejected with error.
  /// Other local copies of this document will continue operating and receiving events normally.
  /// @public
  /// @example
  /// document.close();
  @override
  void close() {
    super.close();
    syncDocumentImpl.detach(listenerUuid);
  }
}
/**
 * Contains Document metadata.
 * @typedef {Object} Document#Metadata
 * @property {Number} [ttl] Specifies the time-to-live in seconds after which the document is subject to automatic deletion.
 * The value 0 means infinity.
 */
/**
 * Applies a transformation to the document data.
 * @callback Document~Mutator
 * @param {Object} currentValue The current data of the document in the cloud.
 * @return {Object} The desired new data for the document or <code>null</code> to gracefully cancel the mutation.
 */
/**
 * Fired when the document is removed, whether the remover was local or remote.
 * @event Document#removed
 * @param {Object} args Arguments provided with the event.
 * @param {Boolean} args.isLocal Equals 'true' if document was removed by local actor, 'false' otherwise.
 * @param {Object} args.previousData Contains a snapshot of the document data before removal.
 * @example
 * document.on('removed', function(args) {
 *   console.log('Document ' + document.sid + ' was removed');
 *   console.log('args.isLocal: ', args.isLocal);
 *   console.log('args.previousData: ', args.previousData);
 * });
 */
/**
 * Fired when the document's contents have changed, whether the updater was local or remote.
 * @event Document#updated
 * @param {Object} args Arguments provided with the event.
 * @param {Object} args.data A snapshot of the document's new contents.
 * @param {Boolean} args.isLocal Equals 'true' if document was updated by local actor, 'false' otherwise.
 * @param {Object} args.previousData Contains a snapshot of the document data before the update.
 * @example
 * document.on('updated', function(args) {
 *   console.log('Document ' + document.sid + ' was updated');
 *   console.log('args.data: ', args.data);
 *   console.log('args.isLocal: ', args.isLocal);
 *   console.log('args.previousData: ', args.previousData);
 * });
 */
