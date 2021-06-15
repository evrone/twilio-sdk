import 'dart:convert';

import 'package:twilio_conversations/src/abstract_classes/storage.dart';
import 'package:twilio_conversations/src/config/sync.dart';

import '../debug.dart';

class SessionStorage implements Storage {
  final SyncConfiguration config;
  final StorageBackend storage;
  String _storageId;
  SessionStorage(this.config, {this.storage});
  String storageKey(String type, String key) => '$_storageId::$type::$key';

  bool get isReady => config.sessionStorageEnabled && _storageId != null;

  @override
  void updateStorageId(storageId) {
    _storageId = storageId;
  }

  Map<String, dynamic> _read(key) {
    try {
      final storedData = storage.getItem(key);
      if (storedData) {
        return jsonDecode(storedData);
      }
    } catch (e) {}
    return null;
  }

  void _store(key, value) {
    try {
      storage.setItem(key, json.encode(value));
    } catch (e) {}
  }

  void _apply(key, patch) {
    final value = _read(key);
    if (value != null) {
      value.addAll(patch);
      _store(key, value);
    }
  }

  @override
  Map<String, dynamic> read(String type, String id) {
    try {
      final storedData = storage.getItem(storageKey(type, id));
      if (storedData) {
        return jsonDecode(storedData);
      }
    } catch (e) {}
    return null;
  }

  @override
  void remove(String type, String sid, {String uniqueName}) {
    if (isReady) {
      try {
        storage.removeItem(storageKey(type, sid));
        if (uniqueName != null) {
          storage.removeItem(storageKey(type, uniqueName));
        }
      } catch (e) {
        Debug.log(e.toString());
      }
    }
  }

  @override
  void store(String type, String id, value) {
    if (isReady) {
      storage.setItem(storageKey(type, id), json.encode(value));
    }
  }

  @override
  void update(String type, String sid, {String uniqueName, patch}) {
    _apply(storageKey(type, sid), patch);
    if (uniqueName != null) {
      _apply(storageKey(type, uniqueName), patch);
    }
  }
}
