/// @class
/// @classdesc Represents an individual element in a Sync List.
/// @alias ListItem
/// @property {int} index The index, within the containing List, of this item. This index is stable;
/// even if lower-indexed Items are removed, this index will remain as is.
/// @property {Object} data The contents of the item.
/// @property {DateTime} dateUpdated Date when the List Item was last updated.

class ListItem<T> {
  /// @private
  /// @constructor
  /// @param {Object} data Item descriptor
  /// @param {Number} data.index Item identifier
  /// @param {String} data.uri Item URI
  /// @param {Object} data.data Item data
  ListItem(
      {String dateExpires,
      T value,
      DateTime dateUpdated,
      int index,
      int lastEventId,
      String revision,
      String url})
      : _dateExpires = dateExpires,
        _dateUpdated = dateUpdated,
        _index = index,
        _lastEventId = lastEventId,
        _revision = revision,
        _value = value,
        _url = url;

  final int _index;
  final String _url;
  final T _value;
  final String _revision;
  final int _lastEventId;
  final DateTime _dateUpdated;
  String _dateExpires;

  String get url => _url;

  String get revision => _revision;

  int get lastEventId => _lastEventId;

  DateTime get dateUpdated => _dateUpdated;

  String get dateExpires => _dateExpires;

  int get index => _index;

  T get value => _value;

  /// @private
  ListItem<T> update(
      int eventId, String revision, T value, DateTime dateUpdated) {
    return ListItem<T>(
        index: _index,
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
