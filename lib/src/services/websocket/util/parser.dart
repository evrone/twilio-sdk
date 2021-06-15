import 'dart:convert';
import 'dart:typed_data';

int byteLength(String s) {
  final escstr = Uri.encodeComponent(s);
  final binstr = escstr.replaceAllMapped(RegExp(r'%([0-9A-F]{2})'), (match) {
    final string = '0x${match.group(0)}';
    return String.fromCharCode(int.parse(string));
  });
  return binstr.length;
}

Uint8List stringToUint8List(String s) {
  final escstr = Uri.encodeComponent(s);
  final binstr = escstr.replaceAllMapped(r'%([0-9A-F]{2})', (match) {
    final string = '0x${match.group(0)}';
    return String.fromCharCode(int.parse(string));
  });
  final ua = Uint8List(binstr.length);
  var l = binstr.length - 1;
  while (l > -1) {
    final ch = binstr[l];
    ua[l] = ch.codeUnitAt(0);
    l -= 1;
  }
  return ua;
}

String uint8ListToString(Uint8List ua) {
  final binstr = String.fromCharCodes(ua);
  final escstr = binstr.replaceAllMapped(RegExp(r'(.)'), (match) {
    var code = match.group(0).codeUnitAt(0).toRadixString(16).toUpperCase();
    if (code.length < 2) {
      code = '0' + code;
    }
    return '%' + code;
  });
  return Uri.decodeComponent(escstr);
}

Map<String, dynamic> getJsonObject(Uint8List list) =>
    json.decode(uint8ListToString(list));

Map<String, dynamic> getMagic(buffer) {
  var strMagic = '';
  var idx = 0;
  for (; idx < buffer.length; ++idx) {
    final chr = String.fromCharCode(buffer[idx]);
    strMagic += chr;
    if (chr == '\r') {
      idx += 2;
      break;
    }
  }
  final magics = strMagic.split(' ');
  return {
    'size': idx,
    'protocol': magics[0],
    'version': magics[1],
    'headerSize': int.tryParse(magics[2])
  };
}

class Parser {
  Parser();
  static Map<String, dynamic> parse(ByteBuffer message) {
    final fieldMargin = 2;
    final dataView = Uint8List.view(message);
    final magic = getMagic(dataView);
    if (magic['protocol'] != 'TWILSOCK' || magic['version'] != 'V3.0') {
      //_1.log.error('unsupported protocol: ${magic.protocol} ver ${magic.version}');
      //throw new Error('Unsupported protocol');
      //fsm.unsupportedProtocol();
      return null;
    }
    Map<String, dynamic> header;
    try {
      header = getJsonObject(
          dataView.sublist(magic.length, magic.length + magic['headerSize']));
    } catch (e) {
      //_1.log.error('failed to parse message header', e, message);
      //throw new Error('Failed to parse message');
      //fsm.protocolError();
      return null;
    }
    //_1.log.debug('message received: ', header.method);
    //_1.log.trace('message received: ', header);
    var payload;
    if (header['payload_size'] > 0) {
      final payloadOffset = fieldMargin + magic['size'] + magic['headerSize'];
      final payloadSize = header['payload_size'];
      if (header['payload_type'] == null ||
          header['payload_type'].indexOf('application/json') == 0) {
        try {
          payload = getJsonObject(
              dataView.sublist(payloadOffset, payloadOffset + payloadSize));
        } catch (e) {
          //_1.log.error('failed to parse message body', e, message);
          //fsm.protocolError();
          return null;
        }
      } else if (header['payload_type'].indexOf('text/plain') == 0) {
        payload = uint8ListToString(
            dataView.sublist(payloadOffset, payloadOffset + payloadSize));
      }
    }
    return {'method': header['method'], 'header': header, 'payload': payload};
  }

  static ByteBuffer createPacket(Map<String, dynamic> header,
      {String payloadString = ''}) {
    header['payload_size'] =
        byteLength(payloadString); // eslint-disable-line camelcase
    final headerString = json.encode(header) + '\r\n';
    final magicString = 'TWILSOCK V3.0 ${byteLength(headerString) - 2} \r\n';
    //_1.log.debug('send request:', magicString + headerString + payloadString);
    final message =
        stringToUint8List(magicString + headerString + payloadString);
    return message.buffer;
  }
}
