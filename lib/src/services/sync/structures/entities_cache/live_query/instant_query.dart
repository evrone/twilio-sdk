import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/errors/syncerror.dart';
import 'package:twilio_conversations/src/services/sync/core/network.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/live_query/core/live_query_implementation.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

/// @class
/// @alias InstantQuery
/// @classdesc Allows repetitive quick searches against a specific Flex data. Unlike a
/// LiveQuery, this result set does not subscribe to any updates and therefore receives no events
/// beyond the initial result set.
///
/// Use the {@link Client#instantQuery} method to create an Instant Query.
///
/// @fires InstantQuery#searchResult
class InstantQuery extends Stendo {
  /// @private
  InstantQuery(
      {String indexName,
      this.queryUri,
      this.insightsUri,
      this.liveQueryCreator,
      this.network,
      this.queryExpression})
      : super() {
    updateIndexName(indexName);
  }

  /// @returns {LiveQuery#ItemsSnapshot} A snapshot of items matching current query expression.
  /// @public
  Map<String, dynamic> get items => _items;

  // private props
  String get type => 'instant_query';
  static String get staticType => 'instant_query';
  final Map _items = {};
  String indexName;
  String queryUri;
  String insightsUri;
  Function liveQueryCreator;
  SyncNetwork network;
  String queryExpression;

  /// Spawns a new search request. The result will be provided asynchronously via the {@link InstantQuery#event:searchResult}
  /// event.
  /// @param {String} queryExpression A query expression to be executed against the given data index. For more information
  /// on the syntax read {@link Client#liveQuery}.
  /// @returns {Future<void>} A promise that resolves when query result has been received.
  /// @public
  Future<void> search(String queryExpression) async {
    _items.clear();
    try {
      final response = await LiveQueryImpl.queryItems(
          network: network, uri: queryUri, queryString: queryExpression);
      this.queryExpression = queryExpression;
      if (response['items'] != null) {
        response['items'].forEach((item) {
          _items[item['key']] = item['data'];
        });
      }
      emit('searchResult', payload: items);
    } catch (_) {
      // (`Error '${err.message}' while executing query '${queryExpression}'`);
      queryExpression = null;
    }
  }

  /// Instantiates a LiveQuery object based on the last known query expression that was passed to the
  /// {@link InstantQuery#search} method. This LiveQuery will start receiving updates with new results,
  /// while current object can be still used to execute repetitive searches.
  /// @returns {Promise<LiveQuery>} A promise which resolves when the LiveQuery object is ready.
  /// @public
  Future subscribe() {
    if (queryExpression == null) {
      // should not be null or undefined
      return Future.error(SyncError('Invalid query', status: 400, code: 54507));
    }
    return liveQueryCreator(indexName, queryExpression);
  }

  String generateQueryUri(String indexName) {
    return UriBuilder(insightsUri)
        .addPathSegment(indexName)
        .addPathSegment('Items')
        .build();
  }

  /// Set new index name
  /// @param {String} indexName New index name to set
  /// @returns void
  /// @public
  void updateIndexName(String indexName) {
    if (indexName.isEmpty) {
      throw Exception('Index name must contain a non-empty string value');
    }
    this.indexName = indexName;
    queryUri = generateQueryUri(this.indexName);
  }
}
