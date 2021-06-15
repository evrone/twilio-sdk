// typedef Headers = Map<String,String>; todo
// typedef Params = Map<String,String>;

import 'package:twilio_conversations/src/enum/twilsock/message_type.dart';
import 'package:twilio_conversations/src/enum/twilsock/method.dart';

class Request {
  Request({this.headers, this.host, this.method, this.params, this.path});
  String host;
  String path;
  Method method;
  Map<String, String> headers;
  Map<String, String> params;
}

class Address {
  Address({this.path, this.params, this.method, this.host, this.headers});
  String method;
  String host;
  String path;
  Map<String, String> headers;
  Map<String, String> params;

  Map toMap() =>
      {'method': method, 'host': host, 'path': path, 'params': params};
}

class Header {
  Header(
      {this.method,
      this.id,
      this.httpRequest,
      this.notificationCtxId,
      this.payloadSize,
      this.payloadType});
  ChannelMessageType method;
  String id;
  String payloadType;
  int payloadSize;
  String notificationCtxId;
  Request httpRequest;
}
