class McsMediaState {
  McsMediaState(
      {this.url,
      this.dateUpdated,
      this.sid,
      this.size,
      this.channelSid,
      this.contentDirectUrl,
      this.contentType,
      this.contentUrl,
      this.dateCreated,
      this.filename,
      this.messageSid,
      this.serviceSid});
  final String sid;
  final String serviceSid;
  final String channelSid;
  final String messageSid;
  final DateTime dateCreated;
  final DateTime dateUpdated;
  final double size;
  final String contentType;
  final String url;
  final String contentUrl;
  final String contentDirectUrl;
  final String filename;
}
