class ClientInfo {
  ClientInfo();
  String sdk = 'dart';
  String envv = '1.12';
  String sdkVer = '1.2.0';
  String type = 'conversations';
  String os = 'dartvm';
  String osVer = 'unknown';
  String pl = 'flutter';
  String plVer = '2';

  Map<String, dynamic> toMap() => {
        'env': sdk,
        'envv': envv,
        'os': os,
        'osv': osVer,
        'osa': '',
        'sdk': sdk,
        'type': type,
      };
}
