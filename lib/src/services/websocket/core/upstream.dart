import 'dart:async';

import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/config/twilsock.dart';
import 'package:twilio_conversations/src/errors/twilsockerror.dart';
import 'package:twilio_conversations/src/errors/twilsockupstreamerror.dart';
import 'package:twilio_conversations/src/services/websocket/models/messages/message.dart';
import 'package:twilio_conversations/src/services/websocket/models/request_descriptor.dart';

import '../../../errors/transportunavailableerror.dart';
import '../channel/twilsock.dart';
import '../models/protocol.dart';
import 'packet_interface.dart';

const REQUEST_TIMEOUT = 20000;

bool isHttpSuccess(int code) {
  return (code >= 200 && code < 300);
}

bool isHttpReply(packet) {
  return packet != null &&
      packet.header != null &&
      packet.header['http_status'] != null;
}

Map<String, dynamic> parseUri(String uri) {
  final rx = RegExp(
      r'^(https?\:)\/\/(([^:\/?#]*)(?:\:([0-9]+))?)(\/[^?#]*)(\?[^#]*|)(#.*|)');
  final match = rx.firstMatch(uri);

  if (match?.group(0) != null) {
    final uriStruct = <String, dynamic>{
      'protocol': match?.group(1),
      'host': match?.group(2),
      'hostname': match?.group(3),
      'port': match?.group(4),
      'pathname': match?.group(5),
      'search': match?.group(6),
      'hash': match?.group(7),
      'params': null
    };
    if ((uriStruct['search']).isNotEmpty) {
      final paramsString = (uriStruct['search'].toString()).substring(1);

      final split = paramsString.split('&').map((el) => el.split('='));
      final Map<String, dynamic> params = {};

      split.forEach((pair) {
        final key = pair.first;
        final value = pair.last;
        if (!params.containsKey(key)) {
          params[key] = value;
        } else if (params[key] is List) {
          params[key].add(value);
        } else {
          params[key] = [params[key], value];
        }
      });
      uriStruct['params'] = params;
    }
    return uriStruct;
  }
  throw TwilsockError('Incorrect URI: ' + uri);
}

Address twilsockAddress(String method, String uri) {
  final parsedUri = parseUri(uri);

  return Address(
      path: parsedUri['pathname'],
      method: method,
      host: parsedUri['host'],
      params: parsedUri['params']);
}

Map<String, dynamic> twilsockParams(String method, String uri,
    Map<String, String> headers, Map<String, dynamic> body, String grant) {
  return {
    'to': twilsockAddress(method, uri).toMap(),
    'headers': headers,
    'body': body,
    'grant': grant
  };
}

class Upstream {
  TwilsockConfiguration config;
  final PacketInterface transport;
  List<RequestDescriptor> pendingMessages = [];
  TwilsockChannel twilsock;
  Upstream(this.transport, this.twilsock, this.config);
  Future<Response> saveMessage(Map<String, dynamic> message) {
    final completer = Completer<Response>();

    final requestDescriptor = RequestDescriptor(
      message: message,
      resolve: completer.complete,
      reject: completer.completeError,
      timeout: REQUEST_TIMEOUT,
    );

    pendingMessages.add(requestDescriptor);
    return completer.future;
  }

  void sendPendingMessages() {
    while (pendingMessages.isNotEmpty) {
      final request = pendingMessages.first;
      // Do not send message if we've rejected its promise already
      if (!request.alreadyRejected) {
        try {
          final message = request.message;
          actualSend(message).then((response) => request.resolve(response));
        } catch (e) {
          request.reject(e);
        }
        ;
        clearTimeout(request.timeout);
      }
    }
    pendingMessages.removeAt(0);
  }

  void rejectPendingMessages() {
    pendingMessages.forEach((message) {
      message.reject(TransportUnavailableError(
          'Unable to connect: ' + twilsock.getTerminationReason));
      clearTimeout(message.timeout);
    });
    pendingMessages.removeRange(0, pendingMessages.length);
  }

  Future<Response> actualSend(Map<String, dynamic> message) async {
    final address = message['to'];
    final headers = message['headers'];
    final body = message['body'];
    final grant = message['grant'] ?? config.activeGrant;
    final httpRequest = Request(
        host: address['host'],
        path: address['path'],
        method: address['method'],
        params: address['params'],
        headers: headers);
    final upstreamMessage = Message(
        grant, headers['Content-Type'] ?? 'application/json', httpRequest);
    final reply = await transport.sendWithReply(upstreamMessage, payload: body);
    if (isHttpReply(reply) &&
        !isHttpSuccess(reply.header['http_status']['code'])) {
      throw TwilsockUpstreamError(reply.header['http_status']['code'],
          reply.header['http_status']['status'], reply.body);
    }
    return Response(
        statusCode: reply.header['http_status'],
        headers: Headers.fromMap(reply.header['http_headers']),
        data: reply.body,
        requestOptions: RequestOptions(
            path: address['path'],
            method: address['method'],
            queryParameters: address['params'],
            headers: headers));
  }

  /// Send an upstream message
  /// @param {string} method The upstream method
  /// @param {string} url URL to send the message to
  /// @param {object} [headers] The message headers
  /// @param {any} [body] The message body
  /// @param {string} [grant] The product grant
  /// @returns {Promise<Result>} Result from remote side

  Future<Response> send(String method, String url, Map<String, String> headers,
      Map<String, dynamic> body, String grant) {
    if (twilsock.isTerminalState) {
      return Future.error(TransportUnavailableError(
          'Unable to connect: ' + twilsock.getTerminationReason));
    }

    final twilsockMessage = twilsockParams(method, url, headers, body, grant);
    if (!twilsock.isConnected) {
      return saveMessage(twilsockMessage);
    }
    return actualSend(twilsockMessage);
  }
}
