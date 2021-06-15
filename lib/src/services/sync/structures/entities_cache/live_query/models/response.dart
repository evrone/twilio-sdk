import 'insights_response_item.dart';

class InsightsQueryResponse {
  InsightsQueryResponse({this.lastEventId, this.items, this.queryId});
  String queryId;
  int lastEventId;
  List<InsightsQueryResponseItem> items;
}
