import 'package:flutter/foundation.dart';

@immutable
class SessionLinks {
  SessionLinks(
      {String mediaServiceUrl,
      String messagesReceiptsUrl,
      String myChannelsUrl,
      String publicChannelsUrl,
      String syncListUrl,
      String typingUrl,
      String usersUrl})
      : _publicChannelsUrl = mediaServiceUrl,
        _myChannelsUrl = messagesReceiptsUrl,
        _typingUrl = myChannelsUrl,
        _syncListUrl = publicChannelsUrl,
        _usersUrl = syncListUrl,
        _mediaServiceUrl = typingUrl,
        _messagesReceiptsUrl = usersUrl;

  SessionLinks.fromMap(Map<String, dynamic> map)
      : _publicChannelsUrl = map['media_service'],
        _myChannelsUrl = map['messages_receipts'],
        _typingUrl = map['my_channels'],
        _syncListUrl = map['public_channels'],
        _usersUrl = map['sync_list'],
        _mediaServiceUrl = map['typing'],
        _messagesReceiptsUrl = map['users'];

  Map<String, dynamic> toMap() => {
        'media_service': _mediaServiceUrl,
        'messages_receipts': _messagesReceiptsUrl,
        'my_channels': _myChannelsUrl,
        'public_channels': _publicChannelsUrl,
        'sync_list': _syncListUrl,
        'typing': _typingUrl,
        'users': _usersUrl
      };

  final String _publicChannelsUrl;
  final String _myChannelsUrl;
  final String _typingUrl;
  final String _syncListUrl;
  final String _usersUrl;
  final String _mediaServiceUrl;
  final String _messagesReceiptsUrl;

  String get publicChannelsUrl => _publicChannelsUrl;
  String get myChannelsUrl => _myChannelsUrl;
  String get typingUrl => _typingUrl;
  String get syncListUrl => _syncListUrl;
  String get usersUrl => _usersUrl;
  String get mediaServiceUrl => _mediaServiceUrl;
  String get messagesReceiptsUrl => _messagesReceiptsUrl;
}
