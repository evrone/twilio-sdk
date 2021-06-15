abstract class CacheItem {
  final int revision;

  CacheItem(this.revision);
  bool get isValid => false;
}
