/// @class Paginator
/// @classdesc Pagination helper class.
///
/// @property {Array} items Array of elements on current page.
/// @property {Boolean} hasNextPage Indicates the existence of next page.
/// @property {Boolean} hasPrevPage Indicates the existence of previous page.
class SyncPaginator<T> {
  /// @constructor
  /// @param {List} items Array of element for current page.
  /// @private
  SyncPaginator(this.items,
      {this.pageSize, String anchor, String direction, this.source})
      : _direction = direction,
        _anchor = anchor;

  int pageSize;
  final String _direction;
  final String _anchor;

  Function source;

  final List<T> items;

  String prevToken;
  String nextToken;
  bool get hasNextPage => nextToken != null && _direction == 'backwards'
      ? _anchor != 'end'
      : items.length == pageSize;

  bool get hasPrevPage => prevToken != null && _direction == 'backwards'
      ? items.length == pageSize &&
          (items.isNotEmpty && items.indexOf(items[0]) != 0)
      : _anchor != 'end';

  /// Request next page.
  /// Does not modify existing object.
  /// @return {Future<Paginator>}
  Future<SyncPaginator> nextPage() {
    if (!hasNextPage) {
      throw Exception('No next page');
    }
    return source(pageSize, items.indexOf(items[items.length - 1]), 'forward');
  }

  /// Request previous page.
  /// Does not modify existing object.
  /// @return {Future<Paginator>}
  Future<SyncPaginator> prevPage() {
    if (!hasPrevPage) {
      throw Exception('No previous page');
    }
    return source(pageSize,
        (items.isNotEmpty ? items.indexOf(items[0]) : 'end'), 'backwards');
  }
}
