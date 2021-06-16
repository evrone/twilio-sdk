import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/abstract_classes/network.dart';
import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/config/client_info.dart';
import 'package:twilio_conversations/src/enum/sync/open_mode.dart';
import 'package:twilio_conversations/src/enum/twilsock/state.dart';
import 'package:twilio_conversations/src/services/notifications/client.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/live_query/models/insights_response_item.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_map/models/map_item.dart';
import 'package:twilio_conversations/src/storage/session_storage.dart';

import '../../config/sync.dart';
import '../../errors/syncerror.dart';
import '../../utils/sanitizer.dart';
import '../../utils/uri_builder.dart';
import '../websocket/client.dart';
import 'core/network.dart';
import 'core/router.dart';
import 'core/subscriptions.dart';
import 'structures/entities_cache/entities_cache.dart';
import 'structures/entities_cache/entity.dart';
import 'structures/entities_cache/live_query/core/live_query_implementation.dart';
import 'structures/entities_cache/live_query/instant_query.dart';
import 'structures/entities_cache/live_query/live_query.dart';
import 'structures/entities_cache/sync_document/core/sync_document_implementation.dart';
import 'structures/entities_cache/sync_document/sync_document.dart';
import 'structures/entities_cache/sync_list/core/sync_list_implementation.dart';
import 'structures/entities_cache/sync_list/sync_list.dart';
import 'structures/entities_cache/sync_map/core/sync_map_implementation.dart';
import 'structures/entities_cache/sync_map/sync_map.dart';
import 'structures/entities_cache/sync_stream/core/sync_stream_implementation.dart';
import 'structures/entities_cache/sync_stream/sync_stream.dart';

const SYNC_PRODUCT_ID = 'data_sync';
const SDK_VERSION = '1.0.0';
Map<String, dynamic> decompose(arg) {
  if (arg == null) {
    return {'mode': OpenMode.createNew};
  } else if (arg is String) {
    return {'id': arg, 'mode': OpenMode.openOrCreate};
  } else if (arg is Map) {
    validateOptionalTtl(arg['ttl']);
    validateId(arg['id']);
    if (arg['mode'] != null) {
      validateMode(arg['mode']);
    }
    final mode = arg['mode'] != null ??
        (arg['id'] != null ? OpenMode.openOrCreate : OpenMode.createNew);
    return arg['mode'] = mode;
  } else {
    return null;
  }
}

/// @class Client
/// @classdesc
/// Client for the Twilio Sync service.
/// @constructor
/// @param {String} token - Twilio access token.
/// @param {Client#ClientOptions} [options] - Options to customize the Client.
/// @example
/// // Using NPM
/// var SyncClient = require('twilio-sync');
/// var syncClient = new SyncClient(token, { logLevel: 'debug' });
///
/// // Using CDN
/// var SyncClient = new Twilio.Sync.Client(token, { logLevel: 'debug' });
///
/// @property {Client#ConnectionState} connectionState - Contains current service connection state.
/// Valid options are ['connecting', 'connected', 'disconnecting', 'disconnected', 'denied', 'error'].
class SyncClient<T> extends Stendo {
  SyncClient(
    String fpaToken, {
    String productId = SYNC_PRODUCT_ID,
    SyncConfiguration config,
    TwilsockClient twilsock,
    NotificationsClient notifications,
    Network network,
    Storage storage,
    SyncRouter router,
    Subscriptions subscriptions,
  })  : _token = fpaToken,
        _router = router,
        _network = network,
        _twilsock = twilsock,
        _notifications = notifications,
        _config = config ?? SyncConfiguration(),
        _storage = storage,
        _subscriptions = subscriptions,
        super() {
    if (fpaToken == null) {
      throw Exception('Sync library needs a valid Twilio token to be passed');
    }

    _twilsock ??= TwilsockClient(_token, productId);

    _twilsock.on('tokenAboutToExpire',
        (ttl) => emit('tokenAboutToExpire', payload: ttl));
    _twilsock.on('tokenExpired', (_) => emit('tokenExpired'));
    _twilsock.on(
        'connectionError', (err) => emit('connectionError', payload: err));

    _notifications ??= NotificationsClient(fpaToken,
        productId: productId, twilsockClient: twilsock);
    ;
    _network = SyncNetwork(_clientMetadata, _config, _twilsock);
    _storage = SessionStorage(_config);

    _twilsock.connect();

    _subscriptions =
        Subscriptions(config: _config, network: _network, router: _router);
    _router = SyncRouter(
        config: config,
        subscriptions: subscriptions,
        notifications: notifications);

    _notifications.on('connectionStateChanged', (_) {
      emit('connectionStateChanged', payload: _notifications.connectionState);
    });
  }

  String _token;
  final SyncConfiguration _config;
  TwilsockClient _twilsock;
  NotificationsClient _notifications;
  SyncNetwork _network;
  Storage _storage;
  SyncRouter _router;
  Subscriptions _subscriptions;
  final ClientInfo _clientMetadata = ClientInfo();

  final EntitiesCache _entities = EntitiesCache();
  var localStorageId;

  /// Current version of Sync client.
  /// @name Client#version
  /// @type String
  /// @readonly
  static String get version => SDK_VERSION;

  TwilsockState get connectionState => _notifications.connectionState;

  /// Returns promise which resolves when library is correctly initialized
  /// Or throws if initialization is impossible
  /// @private
  void ensureReady() async {
    if (!_config.sessionStorageEnabled) {
      return;
    }
    try {
      final storageSettings = await _twilsock.storageId;
      _storage.updateStorageId(storageSettings.id);
    } catch (e) {
      // ('Failed to initialize storage', e);
    }
  }

  void storeRootInSessionCache(
      String type, String id, Map<String, dynamic> value) {
    // can't store without id
    if (!_config.sessionStorageEnabled || id == null) {
      return;
    }
    final valueToStore = value;
    if (type == SyncList.staticType || type == SyncMap.staticType) {
      valueToStore['last_event_id'] = null;
      valueToStore.remove('items');
    }
    _storage.store(type, id, valueToStore);
  }

  dynamic readRootFromSessionCache(String type, {String id}) {
    if (!_config.sessionStorageEnabled || id == null) {
      return null;
    }
    return _storage.read(type, id);
  }

  Future<Map<String, dynamic>> _get(String baseUri, String id,
      {bool optimistic = false}) async {
    if (id == null) {
      throw SyncError('Cannot get entity without id', status: 404);
    }
    final uri = UriBuilder(baseUri)
        .addPathSegment(id)
        .addQueryParam('Include', value: optimistic ? 'items' : null)
        .build();
    final response = await _network.get(uri);
    return response.data;
  }

  Future<Map<String, dynamic>> _createDocument(
      String id, Map<String, dynamic> data, int ttl) {
    final requestBody = {'unique_name': id, 'data': data ?? {}};
    if (ttl != null) {
      requestBody['ttl'] = ttl;
    }
    return _network
        .post(_config.documentsUri, body: requestBody)
        .then((response) {
      final resp = response.data;
      resp['data'] = requestBody['data'];
      return resp.data;
    });
  }

  Future<Map<String, dynamic>> _getDocument(String id) {
    return (readRootFromSessionCache(SyncDocument.staticType, id: id) ??
        _get(_config.documentsUri, id));
  }

  Future<Map<String, dynamic>> _createList(
      String id, String purpose, Map<String, dynamic> context, int ttl) async {
    final requestBody = {
      'unique_name': id,
      'purpose': purpose,
      'context': context
    };
    if (ttl != null) {
      requestBody['ttl'] = ttl;
    }
    return _network
        .post(_config.listsUri, body: requestBody)
        .then((response) => response.data);
  }

  Future<Map<String, dynamic>> _getList(String id) {
    return (readRootFromSessionCache(SyncList.staticType, id: id) ??
        _get(_config.listsUri, id));
  }

  Future<Map<String, dynamic>> _createMap(String id, int ttl) {
    final Map<String, dynamic> requestBody = {'unique_name': id};
    if (ttl != null) {
      requestBody['ttl'] = ttl;
    }
    return _network
        .post(_config.mapsUri, body: requestBody)
        .then((response) => response.data);
  }

  Future<Map<String, dynamic>> _getMap(String id, {optimistic = false}) {
    return (readRootFromSessionCache(SyncMap.staticType, id: id) ??
        _get(_config.mapsUri, id, optimistic: optimistic));
  }

  Future<Map<String, dynamic>> _getStream(String id) {
    return (readRootFromSessionCache(SyncStream.type, id: id) ??
        _get(_config.streamsUri, id, optimistic: false));
  }

  Future<Map<String, dynamic>> _createStream(String id, int ttl) async {
    final Map<String, dynamic> requestBody = {'unique_name': id};
    if (ttl != null) {
      requestBody['ttl'] = ttl;
    }
    final response = await _network.post(_config.streamsUri, body: requestBody);
    return response.data;
  }

  Future<Map<String, dynamic>> _getLiveQuery(String sid) {
    return readRootFromSessionCache(LiveQuery.staticType, id: sid);
  }

  SyncEntity getCached(String id, String type) {
    if (id != null) {
      return _entities.get(id, type);
    }
    return null;
  }

  void removeFromCacheAndSession(String type, String sid, String uniqueName) {
    _entities.remove(sid);
    if (_config.sessionStorageEnabled) {
      _storage.remove(type, sid, uniqueName: uniqueName);
    }
  }

  /// Read or create a Sync Document.
  /// @param {String | Client#OpenOptions} [arg] One of:
  /// <li>Unique name or SID identifying a Sync Document - opens a Document with the given identifier or creates one if it does not exist.</li>
  /// <li>none - creates a new Document with a randomly assigned SID and no unique name.</li>
  /// <li>{@link Client#OpenOptions} object for more granular control.</li>
  /// @return {Promise<Document>} a promise which resolves after the Document is successfully read (or created).
  /// This promise may reject if the Document could not be created or if this endpoint lacks the necessary permissions to access it.
  /// @public
  /// @example
  /// syncClient.document('MyDocument')
  ///   .then(function(document) {
  ///     console.log('Successfully opened a Document. SID: ' + document.sid);
  ///     document.on('updated', function(event) {
  ///       console.log('Received updated event: ', event);
  ///     });
  ///   })
  ///   .catch(function(error) {
  ///     console.log('Unexpected error', error);
  ///   });
  Future<SyncDocument> document(
      {String id,
      Map<String, dynamic> data,
      int ttl,
      OpenMode mode = OpenMode.createNew}) async {
    ensureReady();

    var docDescriptor;
    if (mode == OpenMode.createNew) {
      docDescriptor = _createDocument(id, data, ttl);
    } else {
      final docFromInMemoryCache = getCached(id, SyncDocument.staticType);
      if (docFromInMemoryCache != null) {
        return SyncDocument(docFromInMemoryCache);
      } else {
        try {
          docDescriptor = await _getDocument(id);
        } catch (err) {
          if (err.status != 404 || mode == OpenMode.openExisting) {
            rethrow;
          } else {
            try {
              docDescriptor = _createDocument(id, data, ttl);
            } catch (err) {
              if (err.status == 409) {
                return document(id: id, data: data, ttl: ttl, mode: mode);
              }
            }
          }
        }
      }
    }
    storeRootInSessionCache(SyncDocument.staticType, data['id'], docDescriptor);
    var syncDocumentImpl = SyncDocumentImpl(
      (type, sid, uniqueName) =>
          removeFromCacheAndSession(type, sid, uniqueName),
      network: _network,
      router: _router,
      storage: _storage,
      url: docDescriptor['url'],
      dateUpdated: DateTime.tryParse(docDescriptor['date_updated']),
      dateExpires: docDescriptor['date_expires'],
      lastEventId: docDescriptor['last_event_id'],
      uniqueName: docDescriptor['unique_name'],
      sid: docDescriptor['sid'],
      revision: docDescriptor['revision'],
      data: docDescriptor['data'],
    );
    syncDocumentImpl = _entities.store(syncDocumentImpl);
    return SyncDocument(syncDocumentImpl);
  }

  /// Read or create a Sync Map.
  /// @param {String | Client#OpenOptions} [arg] One of:
  /// <li>Unique name or SID identifying a Sync Map - opens a Map with the given identifier or creates one if it does not exist.</li>
  /// <li>none - creates a new Map with a randomly assigned SID and no unique name.</li>
  /// <li>{@link Client#OpenOptions} object for more granular control.</li>
  /// @return {Promise<Map>} a promise which resolves after the Map is successfully read (or created).
  /// This promise may reject if the Map could not be created or if this endpoint lacks the necessary permissions to access it.
  /// @public
  /// @example
  /// syncClient.map('MyMap')
  ///   .then(function(map) {
  ///     console.log('Successfully opened a Map. SID: ' + map.sid);
  ///     map.on('itemUpdated', function(event) {
  ///       console.log('Received itemUpdated event: ', event);
  ///     });
  ///   })
  ///   .catch(function(error) {
  ///     console.log('Unexpected error', error);
  ///   });
  Future<SyncMap<T>> map(
      {String id, OpenMode mode, bool includeItems, int ttl}) async {
    ensureReady();
    var mapDescriptor;
    if (mode == OpenMode.createNew) {
      mapDescriptor = await _createMap(id, ttl);
    } else {
      final mapFromInMemoryCache = getCached(id, SyncMap.staticType);
      if (mapFromInMemoryCache != null) {
        return SyncMap<T>(mapFromInMemoryCache);
      } else {
        try {
          mapDescriptor = await _getMap(id, optimistic: includeItems);
        } catch (err) {
          if (err.status != 404 || mode == OpenMode.openExisting) {
            rethrow;
          } else {
            try {
              mapDescriptor = await _createMap(id, ttl);
            } catch (err) {
              if (err.status == 409) {
                return map(
                    id: id, mode: mode, includeItems: includeItems, ttl: ttl);
              }
            }
          }
        }
      }
    }
    storeRootInSessionCache(SyncMap.staticType, id, mapDescriptor);
    final List<MapItem> items = mapDescriptor['items'].map((item) => MapItem(
        key: item['key'],
        url: item['url'],
        lastEventId: item['last_event_id'],
        revision: item['revision'],
        dateUpdated: DateTime.tryParse(item['date_updated']),
        dateExpires: item['date_expires'],
        value: item['value']));
    var syncMapImpl = SyncMapImpl(
        (type, sid, uniqueName) =>
            removeFromCacheAndSession(type, sid, uniqueName),
        network: _network,
        router: _router,
        storage: _storage,
        url: mapDescriptor['url'],
        dateUpdated: DateTime.tryParse(mapDescriptor['date_updated']),
        dateExpires: mapDescriptor['date_expires'],
        lastEventId: mapDescriptor['last_event_id'],
        uniqueName: mapDescriptor['unique_name'],
        sid: mapDescriptor['sid'],
        revision: mapDescriptor['revision'],
        links: mapDescriptor['links'],
        items: items);
    syncMapImpl = _entities.store(syncMapImpl);
    return SyncMap(syncMapImpl);
  }

  /// Read or create a Sync List.
  /// @param {String | Client#OpenOptions} [arg] One of:
  /// <li>Unique name or SID identifying a Sync List - opens a List with the given identifier or creates one if it does not exist.</li>
  /// <li>none - creates a new List with a randomly assigned SID and no unique name.</li>
  /// <li>{@link Client#OpenOptions} object for more granular control.</li>
  /// @return {Promise<List>} a promise which resolves after the List is successfully read (or created).
  /// This promise may reject if the List could not be created or if this endpoint lacks the necessary permissions to access it.
  /// @public
  /// @example
  /// syncClient.list('MyList')
  ///   .then(function(list) {
  ///     console.log('Successfully opened a List. SID: ' + list.sid);
  ///     list.on('itemAdded', function(event) {
  ///       console.log('Received itemAdded event: ', event);
  ///     });
  ///   })
  ///   .catch(function(error) {
  ///     console.log('Unexpected error', error);
  ///   });
  Future<SyncList<T>> list(
      {String id,
      OpenMode mode = OpenMode.openOrCreate,
      int ttl,
      String purpose,
      Map<String, dynamic> context}) async {
    ensureReady();
    var listDescriptor;
    if (mode == OpenMode.createNew) {
      listDescriptor = await _createList(id, purpose, context, ttl);
    } else {
      final listFromInMemoryCache = getCached(id, SyncList.staticType);
      if (listFromInMemoryCache != null) {
        return SyncList<T>(listFromInMemoryCache);
      } else {
        try {
          listDescriptor = await _getList(id);
        } catch (err) {
          if (err.status != 404 || mode == OpenMode.openExisting) {
            rethrow;
          } else {
            try {
              listDescriptor = await _createList(id, purpose, context, ttl);
            } catch (err) {
              if (err.status == 409) {
                return list(
                    id: id,
                    ttl: ttl,
                    mode: mode,
                    purpose: purpose,
                    context: context);
              } else {
                rethrow;
              }
            }
          }
        }
      }
    }
    storeRootInSessionCache(SyncList.staticType, id, listDescriptor);
    var syncListImpl = SyncListImpl<T>(
      (type, sid, uniqueName) =>
          removeFromCacheAndSession(type, sid, uniqueName),
      network: _network,
      router: _router,
      storage: _storage,
      url: listDescriptor['url'],
      dateUpdated: DateTime.tryParse(listDescriptor['date_updated']),
      dateExpires: listDescriptor['date_expires'],
      lastEventId: listDescriptor['last_event_id'],
      uniqueName: listDescriptor['unique_name'],
      sid: listDescriptor['sid'],
      revision: listDescriptor['revision'],
      links: listDescriptor['links'],
    );
    syncListImpl = _entities.store(syncListImpl);
    return SyncList<T>(syncListImpl);
  }

  /// Read or create a Sync Message Stream.
  /// @param {String | Client#OpenOptions} [arg] One of:
  /// <li>Unique name or SID identifying a Stream - opens a Stream with the given identifier or creates one if it does not exist.</li>
  /// <li>none - creates a new Stream with a randomly assigned SID and no unique name.</li>
  /// <li>{@link Client#OpenOptions} object for more granular control.</li>
  /// @return {Promise<Stream>} a promise which resolves after the Stream is successfully read (or created).
  /// The flow of messages will begin imminently (but not necessarily immediately) upon resolution.
  /// This promise may reject if the Stream could not be created or if this endpoint lacks the necessary permissions to access it.
  /// @public
  /// @example
  /// syncClient.stream('MyStream')
  ///   .then(function(stream) {
  ///     console.log('Successfully opened a Message Stream. SID: ' + stream.sid);
  ///     stream.on('messagePublished', function(event) {
  ///       console.log('Received messagePublished event: ', event);
  ///     });
  ///   })
  ///   .catch(function(error) {
  ///     console.log('Unexpected error', error);
  ///   });
  Future<SyncStream> stream(arg) async {
    ensureReady();
    final opts = decompose(arg);
    var streamDescriptor;
    if (opts['mode'] == OpenMode.createNew) {
      streamDescriptor = await _createStream(opts['id'], opts['ttl']);
    } else {
      final streamFromInMemoryCache = getCached(opts['id'], SyncStream.type);
      if (streamFromInMemoryCache != null) {
        return SyncStream(streamFromInMemoryCache);
      } else {
        try {
          streamDescriptor = await _getStream(opts['id']);
        } catch (err) {
          if (err.status != 404 || opts['mode'] == OpenMode.openExisting) {
            rethrow;
          } else {
            try {
              streamDescriptor = await _createStream(opts['id'], opts['ttl']);
            } catch (err) {
              if (err.status == 409) {
                return stream(arg);
              } else {
                rethrow;
              }
            }
          }
        }
      }
    }
    storeRootInSessionCache(SyncStream.type, opts['id'], streamDescriptor);
    final streamRemovalHandler = (type, sid, uniqueName) =>
        removeFromCacheAndSession(type, sid, uniqueName);
    var syncStreamImpl = SyncStreamImpl(
      streamRemovalHandler,
      network: _network,
      router: _router,
      storage: _storage,
      url: streamDescriptor['url'],
      dateExpires: streamDescriptor['date_expires'],
      uniqueName: streamDescriptor['unique_name'],
      sid: streamDescriptor['sid'],
      links: streamDescriptor['links'],
    );
    syncStreamImpl = _entities.store(syncStreamImpl);
    return SyncStream(syncStreamImpl);
  }

  /// Gracefully shuts the Sync client down.
  void shutdown() async {
    _subscriptions.shutdown();
    await _twilsock.disconnect();
  }

  /// Set new authentication token.
  /// @param {String} token New token to set.
  /// @return {Future<void>}
  /// @public
  Future<void> updateToken(String token) async {
    if (token == null) {
      return Future.error(Exception('A valid Twilio token should be provided'));
    }
    var result;
    try {
      result = await _twilsock.updateToken(token);
    } catch (error) {
      var a;
      final status =
          (a = error == null ? null : error.reply) == null || a == null
              ? null
              : a.status;
      if ((status == null || status == null ? null : status.code) == 401 &&
          (status == null ? null : status.status) == 'UNAUTHORIZED') {
        throw SyncError('Updated token was rejected by server',
            status: 400, code: 51130);
      }
    }

    if (result != null) {
      _token = result;
    }
  }

  /// For Flex customers only. Establishes a long-running query against Flex data wherein the returned
  /// result set is updated whenever new (or updated) records match the given expression. Updated results
  /// are presented row-by-row according to the lifetime of the returned LiveQuery object.
  ///
  /// @param indexName {String} Must specify one of the Flex data classes for which Live Queries are available.
  /// @param queryExpression {String} A query expression to be executed against the given data index.
  /// Please review <a href="https://www.twilio.com/docs/sync/live-query" target="_blank">Live Query Language</a>
  /// page for Sync Client limits and full list of operators currently supported in query expressions.
  ///
  /// @return {Promise<LiveQuery>} a promise that resolves when the query has been successfully executed.
  /// @public
  /// @example
  /// syncClient.liveQuery('tr-worker', 'data.attributes.worker_name == "Bob"')
  ///     .then(function(args) {
  ///        console.log('Subscribed to live data updates for worker Bob');
  ///        let items = args.getItems();
  ///        Object.entries(items).forEach(([key, value]) => {
  ///          console.log('Search result item key: ' + key);
  ///          console.log('Search result item value: ' + value);
  ///        });
  ///     })
  ///     .catch(function(err) {
  ///        console.log('Error when subscribing to live updates for worker Bob', err);
  ///     });
  Future liveQuery(String indexName, String queryExpression) async {
    ensureReady();

    final queryUri = UriBuilder(_config.insightsUri)
        .addPathSegment(indexName)
        .addPathSegment('Items')
        .build();
    // send query to CDS to get server-generated sid and item list
    final response = await LiveQueryImpl.queryItems(
        network: _network,
        uri: queryUri,
        queryString: queryExpression,
        type: LiveQuery.staticType);
    LiveQueryImpl liveQueryImpl =
        getCached(response['query_id'], LiveQuery.staticType);
    if (liveQueryImpl == null) {
      var descriptor = await _getLiveQuery(response['query_id']);
      descriptor ??= {
        'index_name': indexName,
        'query_expression': queryExpression,
        'sid': response['query_id'],
        'query_uri': queryUri,
        'last_event_id': response['last_event_id']
      };

      final items = response['items'].map((item) => InsightsQueryResponseItem(
          key: item['key'], revision: item['revision'], data: item['data']));

      final liveQueryRemovalHandler = (type, sid, uniqueName) =>
          removeFromCacheAndSession(type, sid, uniqueName);
      liveQueryImpl = LiveQueryImpl(liveQueryRemovalHandler,
          items: items,
          network: _network,
          router: _router,
          storage: _storage,
          indexName: descriptor['indexName'],
          sid: descriptor['sid'],
          queryExpression: descriptor['query_expression'],
          queryUri: descriptor['query_uri'],
          lastEventId: descriptor['last_event_id']);
    }
    storeRootInSessionCache(LiveQuery.staticType, response['query_id'], {
      'last_event_id': liveQueryImpl.lastEventId,
      'sid': liveQueryImpl.sid,
      'queryExpression': queryExpression,
      'query_uri': liveQueryImpl.queryUri,
      'index_name': liveQueryImpl.indexName
    });
    liveQueryImpl = _entities.store(liveQueryImpl);
    return LiveQuery(liveQueryImpl);
  }

  /// For Flex customers only. Creates a query object that can be used to issue one-time queries repeatedly
  /// against the target index.
  ///
  /// @param indexName {String} Must specify one of the Flex data classes for which Live Queries are available.
  /// @return {Promise<InstantQuery>} a promise which resolves after the InstantQuery is successfully created.
  /// @public
  /// @example
  /// syncClient.instantQuery('tr-worker')
  ///    .then(function(q) {
  ///        q.on('searchResult', function(items) {
  ///          Object.entries(items).forEach(([key, value]) => {
  ///             console.log('Search result item key: ' + key);
  ///             console.log('Search result item value: ' + value);
  ///          });
  ///       });
  ///    });
  Future<InstantQuery> instantQuery(String indexName) async {
    ensureReady();
    final liveQueryCreator = (indexName, queryExpression) {
      return liveQuery(indexName, queryExpression);
    };
    final search = InstantQuery(
        indexName: indexName,
        network: _network,
        insightsUri: _config.insightsUri,
        liveQueryCreator: liveQueryCreator);
    return search;
  }
}

///
/// Indicates current state of connection between the client and Sync service.
/// <p>Possible values are as follows:
/// <li>'connecting' - client is offline and connection attempt is in process.
/// <li>'connected' - client is online and ready.
/// <li>'disconnecting' - client is going offline as disconnection is in process.
/// <li>'disconnected' - client is offline and no connection attempt is in process.
/// <li>'denied' - client connection is denied because of invalid JWT access token. User must refresh token in order to proceed.
/// <li>'error' - client connection is in a permanent erroneous state. Client re-initialization is required.
/// @typedef {('connecting'|'connected'|'disconnecting'|'disconnected'|'denied'|'error')} Client#ConnectionState
///
///
/// These options can be passed to Client constructor.
/// @typedef {Object} Client#ClientOptions
/// @property {String} [logLevel='error'] - The level of logging to enable. Valid options
///   (from strictest to broadest): ['silent', 'error', 'warn', 'info', 'debug', 'trace'].
///
///
/// Fired when connection state has been changed.
/// @param {Client#ConnectionState} connectionState Contains current service connection state.
/// @event Client#connectionStateChanged
/// @example
/// syncClient.on('connectionStateChanged', function(newState) {
///   console.log('Received new connection state: ' + newState);
/// });
///
///
/// Fired when connection is interrupted by unexpected reason
/// @property {Object} error - connection error details
/// @property {Boolean} error.terminal - twilsock will stop connection attempts
/// @property {String} error.message - root cause
/// @property {Number} [error.httpStatusCode] - http status code if available
/// @property {Number} [error.errorCode] - Twilio public error code if available
/// @event Client#connectionError
/// @example
/// syncClient.on('connectionError', function(connectionError) {
///   console.log('Connection was interrupted: ' + connectionError.message +
///     ' (isTerminal: ' + connectionError.terminal')');
/// });
///
///
/// Options for opening a Sync Object.
/// @typedef {Object} Client#OpenOptions
/// @property {String} [id] Sync object SID or unique name.
/// @property {'open_or_create' | 'open_existing' | 'create_new'} [mode='open_or_create'] - The mode for opening the Sync object:
/// <li>'open_or_create' - reads a Sync object or creates one if it does not exist.
/// <li>'open_existing' - reads an existing Sync object. The promise is rejected if the object does not exist.
/// <li>'create_new' - creates a new Sync object. If the <i>id</i> property is specified, it will be used as the unique name.
/// @property {Number} [ttl] - The time-to-live of the Sync object in seconds. This is applied only if the object is created.
/// @property {Object} [data={ }] - The initial data for the Sync Document (only applicable to Documents).
/// @example <caption>The following example is applicable to all Sync objects
/// (i.e., <code>syncClient.document(), syncClient.list(), syncClient.map(), syncClient.stream()</code>)</caption>
/// // Attempts to open an existing Document with unique name 'MyDocument'
/// // If no such Document exists, the promise is rejected
/// syncClient.document({
///     id: 'MyDocument',
///     mode: 'open_existing'
///   })
///   .then(...)
///   .catch(...);
///
/// // Attempts to create a new Document with unique name 'MyDocument', TTL of 24 hours and initial data { name: 'John Smith' }
/// // If such a Document already exists, the promise is rejected
/// syncClient.document({
///     id: 'MyDocument',
///     mode: 'create_new',
///     ttl: 86400
///     data: { name: 'John Smith' } // the `data` property is only applicable for Documents
///   })
///   .then(...)
///   .catch(...);
///
///
/// Fired when the access token is about to expire and needs to be updated.
/// The trigger takes place three minutes before the JWT access token expiry.
/// For long living applications, you should refresh the token when either <code>tokenAboutToExpire</code> or
/// <code>tokenExpired</code> events occur; handling just one of them is sufficient.
/// @event Client#tokenAboutToExpire
/// @type {void}
/// @example <caption>The following example illustrates access token refresh</caption>
/// syncClient.on('tokenAboutToExpire', function() {
///   // Obtain a JWT access token: https://www.twilio.com/docs/sync/identity-and-access-tokens
///   var token = '<your-access-token-here>';
///   syncClient.updateToken(token);
/// });
///
///
/// Fired when the access token is expired.
/// In case the token is not refreshed, all subsequent Sync operations will fail and the client will disconnect.
/// For long living applications, you should refresh the token when either <code>tokenAboutToExpire</code> or
/// <code>tokenExpired</code> events occur; handling just one of them is sufficient.
/// @event Client#tokenExpired
/// @type {void}
///
