import 'cache_item.dart';

class Tombstone implements CacheItem {
  Tombstone(this.revision);

  @override
  final int revision;
  @override
  bool get isValid => false;
}
