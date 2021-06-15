import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:twilio_conversations/src/errors/transporterror.dart';

Map<String, dynamic> extractBody(Map<String, dynamic> xhr) {
  final contentType = xhr['Content-Type'].toString().toLowerCase();
  if (contentType == null ||
      contentType.indexOf('application/json') != 0 ||
      xhr['responseText'].length == 0) {
    return xhr['responseText'];
  }
  try {
    return json.decode(xhr['responseText']);
  } catch (e) {
    return xhr['responseText'];
  }
}

Map<String, dynamic> adaptHttpResponse(response) {
  try {
    response.body = json.decode(response.body);
    // ignore: empty_catches
  } catch (e) {} // eslint-disable-line no-empty
  return response;
}

/// Provides generic network interface
class McsTransport {
  static Future<Response> request(String method,
      {String url, Map<String, dynamic> headers, dynamic body}) async {
    final dio = Dio();

    Response response;
    if (method == 'GET') {
      response = await dio.get(url,
          options: Options(
            headers: headers,
            contentType: headers['Content-Type'],
            validateStatus: (status) {
              return status < 540;
            },
          ));
    } else if (method == 'POST') {
      response = await dio.post(url,
          data: body,
          options: Options(
            headers: headers,
            contentType: headers['Content-Type'],
            validateStatus: (status) {
              return status < 540;
            },
          ));
    }

    final header = response.headers;
    final data = response.data;

    if (200 <= response.statusCode && response.statusCode < 300) {
      return response;
    } else {
      final status = response.statusMessage;
      final message = '${response.statusCode}: [$status] ${json.encode(data)}';
      return Future.error(TransportError(
          message: message,
          body: data,
          status: status,
          headers: header,
          code: response.statusCode));
    }
  }

  /// Make a GET request by given URL
  Future<Response> get(String url, Map<String, dynamic> headers) {
    return McsTransport.request('GET', url: url, headers: headers);
  }

  /// Make a POST request by given URL
  Future<Response> post(
      String url, Map<String, dynamic> headers, dynamic body) {
    return McsTransport.request('POST', url: url, headers: headers, body: body);
  }
}
