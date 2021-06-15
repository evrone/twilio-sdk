class PacketResponse {
  PacketResponse({this.id, this.body, this.header});
  String id;
  Map<String, dynamic> header;
  Map<String, dynamic> body;
}
