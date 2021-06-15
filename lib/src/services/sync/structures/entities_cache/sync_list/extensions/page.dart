class SyncListPage {
  SyncListPage(
      {this.status,
      this.channelSid,
      this.channel,
      this.descriptor,
      this.notificationLevel,
      this.messages,
      this.lastConsumedMessageIndex,
      this.roster});
  String channelSid;
  String status;
  String channel;
  String messages;
  String roster;
  int lastConsumedMessageIndex;
  String notificationLevel;
  var descriptor;
}
