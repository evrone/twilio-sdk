import 'session_links.dart';

class SessionContext {
  SessionContext(
      {String type,
      String identity,
      Map<String, dynamic> channels,
      Map<String, dynamic> myChannels,
      Map<String, dynamic> userInfo,
      SessionLinks links,
      String apiVersion,
      String endpointPlatform,
      double httpCacheInterval,
      double consumptionReportInterval,
      this.reachabilityEnabled})
      : _type = type,
        _identity = identity,
        _channels = channels,
        _myChannels = myChannels,
        _userInfo = userInfo,
        _links = links,
        _apiVersion = apiVersion,
        _endpointPlatform = endpointPlatform,
        _httpCacheInterval = httpCacheInterval,
        _consumptionReportInterval = consumptionReportInterval;
  final String _identity;
  final Map<String, dynamic> _userInfo;
  final SessionLinks _links;
  final Map<String, dynamic> _myChannels;
  final Map<String, dynamic> _channels;
  final String _type;
  final String _apiVersion;
  final String _endpointPlatform;
  final double _httpCacheInterval;
  final double _consumptionReportInterval;
  bool reachabilityEnabled = false;
  String get identity => _identity;
  Map<String, dynamic> get userInfo => _userInfo;
  SessionLinks get links => _links;
  Map<String, dynamic> get myChannels => _myChannels;
  Map<String, dynamic> get channels => _channels;
  String get type => _type;
  String get apiVersion => _apiVersion;
  String get endpointPlatform => _endpointPlatform;
  double get httpCacheInterval => _httpCacheInterval;
  double get consumptionReportInterval => _consumptionReportInterval;

  SessionContext.fromMap(Map<String, dynamic> map)
      : _identity = map['identity'],
        _type = map['type'],
        _channels = map['channels'],
        _myChannels = map['my_channels'],
        _userInfo = map['user_info'],
        _links = map['links'],
        _apiVersion = map['api_version'],
        _endpointPlatform = map['endpoint_platform'],
        _httpCacheInterval = map['httpCache_interval'],
        _consumptionReportInterval = map['consumption_report_interval'];

  Map<String, dynamic> toMap() => {
        'identity': _identity,
        'type': _type,
        'channels': _channels,
        'my_channels': _myChannels,
        'user_info': _userInfo,
        'links': _links.toMap(),
        'api_version': _apiVersion,
        'endpoint_platform': _endpointPlatform,
        'http_cache_interval': _httpCacheInterval,
        'consumption_report_interval': _consumptionReportInterval
      };
}
