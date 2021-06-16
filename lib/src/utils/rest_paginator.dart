import 'package:twilio_conversations/src/abstract_classes/paginator.dart';

/// @class Paginator
/// @classdesc Pagination helper class
///
/// @property {Array} items Array of elements on current page
/// @property {boolean} hasNextPage Indicates the existence of next page
/// @property {boolean} hasPrevPage Indicates the existence of previous page

class RestPaginator<T> implements Paginator {
  RestPaginator({this.items, this.source, this.prevToken, this.nextToken});

  @override
  Function source;

  @override
  final List<T> items;

  String prevToken;
  String nextToken;

  Map<String, dynamic> state;
  @override
  bool get hasNextPage => nextToken != null;
  @override
  bool get hasPrevPage => prevToken != null;

  Future<RestPaginator<T>> nextPage() =>
      hasNextPage ? source(nextToken) : Future.error(Exception('No next page'));

  Future<RestPaginator<T>> prevPage() => hasPrevPage
      ? source(prevToken)
      : Future.error(Exception('No previous page'));

  int pageSize;
}
