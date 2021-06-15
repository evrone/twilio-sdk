import 'abstract_message.dart';

class ContinuationTokenStatus {
  bool reissued;
  String reissueReason;
  String reissueMessage;
}

class InitReply extends AbstractMessage {
  String continuationToken;
  ContinuationTokenStatus continuationTokenStatus;
  var offlineStorage;
  var initRegistrations;
  var debugInfo;
  Set<String> confirmedCapabilities;
  InitReply(
      String id,
      this.continuationToken,
      this.continuationTokenStatus,
      this.offlineStorage,
      this.initRegistrations,
      this.debugInfo,
      this.confirmedCapabilities)
      : super(id: id);
}
