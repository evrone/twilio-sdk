class Metadata {
  static Map<String, String> getMetadata(options) {
    final Map overrides =
        options && options.clientMetadata ? options.clientMetadata : {};
    final fieldNames = [
      'ver',
      'env',
      'envv',
      'os',
      'osv',
      'osa',
      'type',
      'sdk',
      'sdkv',
      'dev',
      'devv',
      'devt',
      'app',
      'appv'
    ];
    final defaults = {
      'env': 'dart',
      'envv': '1.12',
      'os': 'DartVM',
      'osv': '',
      'osa': '',
      'sdk': 'js-default'
    };

    return defaults;
  }
}
