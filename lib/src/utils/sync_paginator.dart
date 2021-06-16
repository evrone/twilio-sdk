import 'package:twilio_conversations/src/abstract_classes/paginator.dart';

/// @class Paginator
/// @classdesc Pagination helper class.
///
/// @property {Array} items Array of elements on current page.
/// @property {Boolean} hasNextPage Indicates the existence of next page.
/// @property {Boolean} hasPrevPage Indicates the existence of previous page.
class SyncPaginator<T> implements Paginator {
  /// @constructor
  /// @param {List} items Array of element for current page.
  /// @private
  SyncPaginator(this.items,
      {this.pageSize,
      String anchor,
      String direction,
      this.source,
      bool hasNxtPageOverride,
      bool hasPrvPageOverride,
      Future<SyncPaginator> Function() nextPageOverride,
      Future<SyncPaginator> Function() prevPageOverride})
      : _hasNxtPageOverride = hasNxtPageOverride,
        _hasPrvPageOverride = hasPrvPageOverride,
        _nextPageOverride = nextPageOverride,
        _prevPageOverride = prevPageOverride,
        _direction = direction,
        _anchor = anchor;

  int pageSize;
  final String _direction;
  final String _anchor;

  final bool _hasNxtPageOverride;
  final bool _hasPrvPageOverride;

  final Future<SyncPaginator> Function() _nextPageOverride;
  final Future<SyncPaginator> Function() _prevPageOverride;

  Function _nextPage() {
    if (!hasNextPage) {
      throw Exception('No next page');
    }
    return source(pageSize, items.indexOf(items[items.length - 1]), 'forward');
  }

  Function _prevPage() {
    if (!hasPrevPage) {
      throw Exception('No previous page');
    }
    return source(pageSize,
        (items.isNotEmpty ? items.indexOf(items[0]) : 'end'), 'backwards');
  }

  @override
  Function source;

  @override
  final List<T> items;

  String prevToken;
  String nextToken;
  @override
  bool get hasNextPage =>
      _hasNxtPageOverride ?? (nextToken != null && _direction == 'backwards')
          ? _anchor != 'end'
          : items.length == pageSize;

  @override
  bool get hasPrevPage =>
      _hasPrvPageOverride ??
      (prevToken != null && _direction == 'backwards'
          ? items.length == pageSize &&
              (items.isNotEmpty && items.indexOf(items[0]) != 0)
          : _anchor != 'end');

  /// Request next page.
  /// Does not modify existing object.
  /// @return {Future<Paginator>}

  Future<SyncPaginator> Function() get nextPage =>
      _nextPageOverride ?? _nextPage;

  /// Request previous page.
  /// Does not modify existing object.
  /// @return {Future<Paginator>}

  Future<SyncPaginator> Function() get prevPage =>
      _prevPageOverride ?? _prevPage;
}
