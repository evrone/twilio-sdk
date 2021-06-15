class UriBuilder {
  UriBuilder(this.base);
  final String base;
  final List<String> args = [];
  final List<String> paths = [];

  UriBuilder addPathSegment(String name) {
    paths.add(Uri.encodeComponent(name));
    return this;
  }

  UriBuilder addQueryParam(String name, {value}) {
    if (value != null) {
      args.add(Uri.encodeComponent(name) + '=' + Uri.encodeComponent(value));
    }
    return this;
  }

  String build() {
    var result = base;
    if (paths.isNotEmpty) {
      result += '/' + paths.join('/');
    }
    if (args.isNotEmpty) {
      result += '?' + args.join('&');
    }
    return result;
  }
}
