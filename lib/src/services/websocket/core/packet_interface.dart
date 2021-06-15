import 'dart:async';
import 'dart:convert';

import 'package:twilio_conversations/src/config/twilsock.dart';
import 'package:twilio_conversations/src/errors/twilsockerror.dart';
import 'package:twilio_conversations/src/services/websocket/channel/websocket_channel.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/abstract_message.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/close.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/init.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/initReply.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/reply.dart';
import 'package:twilio_conversations/src/services/websocket/models/packet_response.dart';
import 'package:twilio_conversations/src/services/websocket/models/request_descriptor.dart';
import 'package:uuid/uuid.dart';

import '../../../errors/twilsockreplyerror.dart';
import '../util/metadata.dart';
import '../util/parser.dart';

const REQUEST_TIMEOUT = 30000;
bool isHttpSuccess(int code) => (code >= 200 && code < 300);

void clearTimeout(Timer timeout) {
  timeout.cancel();
}

class PacketInterface {
  PacketInterface(this.channel, this.config) {
    channel.on('reply', (reply) => processReply(reply));
    channel.on('disconnected', (_) {
      activeRequests.values.forEach((descriptor) {
        clearTimeout(descriptor.timeout);
        descriptor.reject(TwilsockError('disconnected'));
      });
      activeRequests.clear();
    });
  }
  final TwilsockConfiguration config;
  final Map<String, RequestDescriptor> activeRequests = {};
  final WebSocketChannel channel;

  bool get isConnected => channel.isConnected;
  void processReply(Reply reply) {
    final request = activeRequests[reply.id];
    if (request != null) {
      clearTimeout(request.timeout);
      activeRequests.remove(reply.id);
      if (!isHttpSuccess(reply.status.code)) {
        request.reject(TwilsockReplyError(
            'Transport failure: ' + reply.status.status, reply));
        // ('message rejected');
      } else {
        request.resolve(reply);
      }
    }
  }

  void storeRequest(String id, Function resolve, Function reject) {
    final requestDescriptor = RequestDescriptor(
        id: id,
        resolve: resolve,
        reject: reject,
        timeout: REQUEST_TIMEOUT,
        errorMessage: 'Twilsock: request timeout: ' + id);
    activeRequests[id] = requestDescriptor;
  }

  void shutdown() {
    activeRequests.values.forEach((descriptor) {
      clearTimeout(descriptor.timeout);
      descriptor.reject(TwilsockError('Twilsock: request cancelled by user'));
    });
    activeRequests.clear();
  }

  Future<InitReply> sendInit() async {
    //logger_1.log.trace('sendInit');
    final metadata = Metadata.getMetadata(config);
    final message = Init(config.token, config.continuationToken, metadata,
        config.initRegistrations, config.tweaks);
    final response = await sendWithReply(message);
    return InitReply(
        response.id,
        response.header['continuation_token'],
        response.header['continuation_token_status'],
        response.header['offline_storage'],
        response.header['init_registrations'],
        response.header['debug_info'],
        <String>{}..add(response.header['capabilities']));
  }

  void sendClose() {
    final message = Close();
    //@todo send telemetry AnyEventsIncludingUnfinished
    send(message);
  }

  Future<PacketResponse> sendWithReply(AbstractMessage header,
      {Map<String, dynamic> payload}) {
    final completer = Completer<PacketResponse>();
    final id = send(header, payload: payload);
    storeRequest(id, completer.complete, completer.completeError);
    return completer.future;
  }

  String send(AbstractMessage header, {Map<String, dynamic> payload}) {
    header.id ??= 'TM${Uuid().v4()}';
    final message = Parser.createPacket(header.toMap(),
        payloadString: json.encode(payload));
    try {
      channel.send(message);
    } catch (e) {
      // ('failed to send ', header, e);
      // (e.stack);
      //throw e;
    }
    return header.id;
  }
}
