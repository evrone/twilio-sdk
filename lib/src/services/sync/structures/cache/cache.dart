import 'package:twilio_conversations/src/services/sync/structures/tree_map/tree.dart';

import 'models/cache_item.dart';
import 'models/entry.dart';
import 'models/tombstone.dart';

class Cache<Key, Value> {
  TreeMap<Key, CacheItem> items = TreeMap<Key, CacheItem>();

  Value store(Key key, Value value, int revision) {
    final Entry entry = items.get(key);
    if (entry != null && entry.revision > revision) {
      if (entry.isValid) {
        return entry.value;
      }
      return null;
    }
    items.set(key, Entry<Value>(value, revision: revision));
    return value;
  }

  void delete(Key key, int revision, {bool force = false}) {
    final CacheItem curr = items.get(key);
    if (curr == null ||
        curr.revision < revision ||
        (curr != null &&
            force == true) /* forced delete when revision is unknown */) {
      items.set(key, Tombstone(revision));
    }
  }

  bool isKnown(Key key, int revision) {
    final curr = items.get(key);
    return curr != null && curr.revision >= revision;
  }

  Value get(Key key) {
    final Entry entry = items.get(key);
    if (entry != null && entry.isValid) {
      return entry.value;
    }
    return null;
  }

  bool has(Key key) {
    final entry = items.get(key);
    return entry != null && (entry as dynamic).isValid;
  }

  void forEach(Function(Key, Value) callback) async {
    final iterator = items.iterator();
    if (items != null) {
      while (iterator.moveNext()) {
        if (iterator.current.value.isValid &&
            iterator.current.value is Entry<Value>) {
          callback(iterator.current.key,
              (iterator.current.value as Entry<Value>).value);
        }
      }
    }
  }
}
