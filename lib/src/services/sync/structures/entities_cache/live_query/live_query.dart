import 'package:twilio_conversations/src/services/sync/core/closable.dart';

import 'core/live_query_implementation.dart';

/// @class
/// @alias LiveQuery
/// @classdesc Represents a long-running query against Flex data wherein the returned result set
///     subsequently receives pushed updates whenever new (or updated) records would match the
///     given expression. Updated results are presented row-by-row until this query is explicitly
///     closed.
///
///     Use the {@link Client#liveQuery} method to create a live query.
///
/// @property {String} sid The immutable identifier of this query object, assigned by the system.
///
/// @fires LiveQuery#itemUpdated
/// @fires LiveQuery#itemRemoved
class LiveQuery extends Closeable {
  /// @private
  LiveQuery(this.liveQueryImpl) : super() {
    liveQueryImpl.attach(this);
  }

  LiveQueryImpl liveQueryImpl;
  // private props

  String get type => liveQueryImpl.type;
  static String get staticType => LiveQueryImpl.staticType;

  int get lastEventId => liveQueryImpl.lastEventId;

  // public
  String get sid => liveQueryImpl.sid;

  /// Closes this query instance and unsubscribes from further service events.
  /// This will eventually stop the physical inflow of updates over the network, when all other instances of this query are closed as well.
  /// @public
  @override
  void close() {
    super.close();
    liveQueryImpl.detach(listenerUuid);
  }

  /// @returns {LiveQuery#ItemsSnapshot} A snapshot of items matching the current query expression.
  /// @public
  Map<String, dynamic> getItems() {
    ensureNotClosed();
    return liveQueryImpl.getItems();
  }
}
