import 'sync_paginator.dart';

/// @class Paginator
/// @classdesc Pagination helper class
///
/// @property {Array} items Array of elements on current page
/// @property {boolean} hasNextPage Indicates the existence of next page
/// @property {boolean} hasPrevPage Indicates the existence of previous page

class RestPaginator<T> implements SyncPaginator<T> {
  RestPaginator({this.items, this.source, this.prevToken, this.nextToken});

  @override
  Function source;

  @override
  final List<T> items;

  @override
  String prevToken;
  @override
  String nextToken;

  Map<String, dynamic> state;
  @override
  bool get hasNextPage => nextToken != null;
  @override
  bool get hasPrevPage => prevToken != null;

  @override
  Future<RestPaginator<T>> nextPage() =>
      hasNextPage ? source(nextToken) : Future.error(Exception('No next page'));

  @override
  Future<RestPaginator<T>> prevPage() => hasPrevPage
      ? source(prevToken)
      : Future.error(Exception('No previous page'));

  @override
  int pageSize;
}
