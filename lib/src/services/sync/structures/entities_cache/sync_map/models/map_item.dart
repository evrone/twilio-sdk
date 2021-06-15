/// @class
/// @classdesc Represents an individual element in a Sync Map.`
/// @alias MapItem
/// @property [String] key The identifier that maps to this item within the containing Map.
/// @property [Object] data The contents of the item.
/// @property [DateTime] dateUpdated Date when the Map Item was last updated, given in UTC ISO 8601 format (e.g., '2018-04-26T15:23:19.732Z')

class MapItem<T> {
  /// @private
  /// @constructor
  MapItem(
      {String key,
      String url,
      int lastEventId,
      String revision,
      DateTime dateUpdated,
      String dateExpires,
      T value})
      : _url = url,
        _key = key,
        _lastEventId = lastEventId,
        _revision = revision,
        _dateUpdated = dateUpdated,
        _dateExpires = dateExpires,
        _value = value;

  final String _key;
  final String _url;
  final String _revision;
  final int _lastEventId;
  final DateTime _dateUpdated;
  String _dateExpires;
  final T _value;

  String get uri => _url;

  String get revision => _revision;

  int get lastEventId => _lastEventId;

  String get dateExpires => _dateExpires;

  String get key => _key;

  T get data => _value;

  DateTime get dateUpdated => _dateUpdated;

  /// @private
  MapItem<T> update(
      int eventId, String revision, T value, DateTime dateUpdated) {
    return MapItem<T>(
        key: _key,
        url: _url,
        lastEventId: eventId ?? _lastEventId,
        revision: revision ?? _revision,
        dateUpdated: dateUpdated ?? _dateUpdated,
        dateExpires: _dateExpires,
        value: value ?? _value);
  }

  /// @private
  void updateDateExpires(String dateExpires) {
    _dateExpires = dateExpires;
  }
}
