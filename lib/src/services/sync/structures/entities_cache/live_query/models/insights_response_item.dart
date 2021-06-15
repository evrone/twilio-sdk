class InsightsQueryResponseItem<K, T> {
  InsightsQueryResponseItem({this.key, this.revision, this.data});
  K key;
  T data;
  int revision;
}
