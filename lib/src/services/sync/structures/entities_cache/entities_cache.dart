import 'entity.dart';

/// Container for entities which are known by the client
/// It's needed for deduplication when client obtain the same object several times
class EntitiesCache {
  final Map<String, String> names = {};
  final Map<String, SyncEntity> entities = {};

  SyncEntity store(SyncEntity entity) {
    final stored = entities[entity.sid];
    if (stored != null) {
      return stored;
    }
    entities[entity.sid] = entity;
    if (entity.uniqueName != null) {
      names[entity.type + '::' + entity.uniqueName] = entity.sid;
    }
    return entity;
  }

  SyncEntity getResolved(String id, String type) {
    final resolvedSid = names[type + '::' + id];
    return resolvedSid != null ? entities[resolvedSid] : null;
  }

  SyncEntity get(String id, String type) {
    return entities[id] ?? getResolved(id, type);
  }

  void remove(String sid) {
    final cached = entities[sid];
    if (cached != null) {
      entities.remove(sid);
      if (cached.uniqueName != null) {
        names.remove(cached.type + '::' + cached.uniqueName);
      }
    }
  }
}
