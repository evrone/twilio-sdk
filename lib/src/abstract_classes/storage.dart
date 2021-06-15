abstract class StorageBackend {
  void setItem(String key, String value);
  dynamic getItem(String key);
  void removeItem(String key);
}

abstract class Storage {
  dynamic store(String type, String id, value);
  dynamic read(String type, String id);
  dynamic update(String type, String id, {String uniqueName, patch});
  dynamic remove(String type, String sid, {String uniqueName});
  dynamic updateStorageId(String storageId);
}
