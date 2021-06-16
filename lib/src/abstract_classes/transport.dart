abstract class Transport {
  bool get isConnected;
  dynamic get state;
  Future get(String url, Map<String, dynamic> headers, String grant);
  Future post(String url, Map<String, dynamic> headers,
      Map<String, dynamic> body, String grant);
  Future put(String url, Map<String, dynamic> headers,
      Map<String, dynamic> body, String grant);
  Future delete(String url, Map<String, dynamic> headers, String grant);
}
