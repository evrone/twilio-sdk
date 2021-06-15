import 'package:twilio_conversations/src/abstract_classes/network.dart';
import 'package:twilio_conversations/src/core/session/models/session_links.dart';
import 'package:twilio_conversations/src/services/sync/structures/entities_cache/sync_list/sync_list.dart';
import 'package:twilio_conversations/src/utils/rest_paginator.dart';
import 'package:twilio_conversations/src/utils/uri_builder.dart';

import 'page.dart';

extension Pagination on SyncList {
  Future<RestPaginator<SyncListPage>> getPage(
      {Network network, String pageToken, SessionLinks links}) async {
    final url = UriBuilder(links.syncListUrl)
        .addQueryParam('PageToken', value: pageToken)
        .build();
    final response = await network.get(url);
    return RestPaginator(
        items:
            response.data['channels'].map((x) => SyncListPage(descriptor: x)),
        source: (pageToken) =>
            getPage(pageToken: pageToken, network: network, links: links),
        prevToken: response.data['meta']['previous_token'],
        nextToken: response.data['meta']['next_token']);
  }
}
