import 'dart:async';

import 'package:twilio_conversations/src/errors/sessionerror.dart';

import 'session/session.dart';

class ConsumptionReportRequest {
  ConsumptionReportRequest({this.entry, this.promises});
  final List<Completer> promises;
  ConsumptionReportEntry entry;
}

class ConsumptionReportEntry {
  ConsumptionReportEntry(
      {this.channelSid,
      this.currentConversationLastReadIndex,
      this.messageIdx});
  String channelSid;
  int messageIdx;
  int currentConversationLastReadIndex;
}

/// @classdesc Provides read horizon management functionality
class ReadHorizon {
  ReadHorizon(this.session);

  Session session;
  final Map<String, ConsumptionReportRequest> readHorizonRequests = {};
  Timer readHorizonUpdateTimer;

  Future<int> getReportInterval() async {
    return (await session
            .getConsumptionReportInterval()
            .then((seconds) => seconds * 1000))
        .round();
  }

  void delayedSendReadHorizon(int delay) {
    if (readHorizonUpdateTimer != null) {
      return;
    }
    sendConsumptionReport(true);
    readHorizonUpdateTimer = Timer(Duration(milliseconds: delay), () {
      sendConsumptionReport(false);
    });
  }

  void sendConsumptionReport(bool keepTimer) async {
    final reports = [];
    final promises = {};
    readHorizonRequests.forEach((conversationSid, request) {
      reports.add(request.entry);
      promises[conversationSid] = request.promises;
    });
    if (reports.isNotEmpty) {
      var response;
      try {
        response = await session
            .addCommand('consumptionReportV2', {'report': reports});
      } catch (e) {
        processConsumptionReportError(e, promises);
      }
      processConsumptionReportResponse(response, promises);
    }
    if (!keepTimer) {
      readHorizonUpdateTimer.cancel();
      readHorizonUpdateTimer = null;
    }
    readHorizonRequests.clear();
  }

  void processConsumptionReportResponse(
      response, Map<String, List<Completer>> promises) {
    if (response != null &&
        response.report &&
        (response.report is List && response.report.length > 0)) {
      (response.report as List).forEach((entry) {
        final responseEntry = entry;
        if (promises.containsKey(responseEntry.channelSid)) {
          var unreadMessagesCount;
          if (responseEntry.unreadMessagesCount != null) {
            unreadMessagesCount = responseEntry.unreadMessagesCount;
          }
          promises[responseEntry.channelSid]
              .forEach((promise) => promise.complete(unreadMessagesCount));
          promises.remove(responseEntry.channelSid);
        }
      });
    }
    processConsumptionReportError(
        ConversationsSessionError(
            'Error while setting LastReadMessageIndex', null),
        promises);
  }

  void processConsumptionReportError(
      err, Map<String, List<Completer>> promises) {
    promises.values.forEach((conversationPromises) =>
        conversationPromises.forEach((promise) => promise.completeError(err)));
  }

  /// Updates read horizon value without any checks
  Future updateLastReadMessageIndexForConversation(
      String conversationSid, int messageIdx) {
    final completer = Completer();
    addPendingConsumptionHorizonRequest(
        conversationSid,
        ConsumptionReportEntry(
            channelSid: conversationSid, messageIdx: messageIdx),
        completer);
    getReportInterval().then((delay) => delayedSendReadHorizon(delay));
    return completer.future;
  }

  /// Move read horizon forward
  Future advanceLastReadMessageIndexForConversation(String conversationSid,
      int messageIdx, int currentConversationLastReadIndex) {
    final currentHorizon = readHorizonRequests[conversationSid];
    final completer = Completer();
    if (currentHorizon != null && currentHorizon.entry != null) {
      if (currentHorizon.entry.messageIdx >= messageIdx) {
        addPendingConsumptionHorizonRequest(
            conversationSid, currentHorizon.entry, completer);
      } else {
        addPendingConsumptionHorizonRequest(
            conversationSid,
            ConsumptionReportEntry(
                channelSid: conversationSid, messageIdx: messageIdx),
            completer);
      }
    } else {
      if ((currentConversationLastReadIndex != null) &&
          messageIdx < currentConversationLastReadIndex) {
        addPendingConsumptionHorizonRequest(
            conversationSid,
            ConsumptionReportEntry(
                channelSid: conversationSid,
                messageIdx: messageIdx,
                currentConversationLastReadIndex:
                    currentConversationLastReadIndex),
            completer);
      } else {
        addPendingConsumptionHorizonRequest(
            conversationSid,
            ConsumptionReportEntry(
                channelSid: conversationSid, messageIdx: messageIdx),
            completer);
      }
    }
    getReportInterval().then((delay) => delayedSendReadHorizon(delay));
    return completer.future;
  }

  void addPendingConsumptionHorizonRequest(
      String conversationSid, ConsumptionReportEntry entry, Completer promise) {
    if (readHorizonRequests.containsKey(conversationSid)) {
      final request = readHorizonRequests[conversationSid];
      request.entry = entry;
      request.promises.add(promise);
    } else {
      readHorizonRequests[conversationSid] =
          ConsumptionReportRequest(entry: entry, promises: [promise]);
    }
  }
}
