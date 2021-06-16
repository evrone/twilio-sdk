abstract class Paginator<T> {
  bool get hasNextPage;
  bool get hasPrevPage;

  Function get source;

  List<T> get items;
}
