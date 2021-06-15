import 'cache_item.dart';

class Entry<Val> implements CacheItem {
  Entry(this.value, {this.revision = 0});
  Val value;
  @override
  final int revision;
  @override
  bool get isValid => true;
}
