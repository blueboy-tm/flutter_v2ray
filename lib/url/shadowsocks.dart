import 'dart:convert';

import 'package:flutter_v2ray/url/url.dart';

class ShadowSocksURL extends V2RayURL {
  ShadowSocksURL({required super.url}) {
    if (!url.startsWith('ss://')) {
      throw ArgumentError('url is invalid');
    }
    // SIP002: ss://base64(method:password)@host:port and
    //          ss://method:password@host:port.
    // Legacy: ss://base64(method:password@host:port).
    final authority = url.substring(5).split('#').first.split('?').first;
    Uri? parsed;
    if (!authority.contains('@')) {
      try {
        final decoded =
            utf8.decode(base64Decode(base64.normalize(authority)));
        parsed = Uri.tryParse('ss://$decoded');
      } catch (_) {
        throw ArgumentError('url is invalid');
      }
    } else {
      parsed = Uri.tryParse(url);
    }
    if (parsed == null || parsed.host.isEmpty) {
      throw ArgumentError('url is invalid');
    }
    uri = parsed;

    var credentials = uri.userInfo;
    if (!credentials.contains(':')) {
      try {
        credentials =
            utf8.decode(base64Decode(base64.normalize(credentials)));
      } catch (_) {
        throw ArgumentError('Invalid Shadowsocks credentials');
      }
    }
    final splitAt = credentials.indexOf(':');
    if (splitAt <= 0) {
      throw ArgumentError('Invalid Shadowsocks credentials');
    }
    method = Uri.decodeComponent(credentials.substring(0, splitAt));
    password = Uri.decodeComponent(credentials.substring(splitAt + 1));
    if (method.isEmpty || password.isEmpty) {
      throw ArgumentError('Invalid Shadowsocks credentials');
    }

    final params = uri.queryParameters;
    if (params.isNotEmpty) {
      final sni = populateTransportSettings(
        transport: params['type'] ?? 'tcp',
        headerType: params['headerType'],
        host: params['host'],
        path: params['path'],
        seed: params['seed'],
        quicSecurity: params['quicSecurity'],
        key: params['key'],
        mode: params['mode'],
        serviceName: params['serviceName'],
      );
      populateTlsSettings(
        streamSecurity: params['security'] ?? '',
        allowInsecure: allowInsecure,
        sni: params['sni'] ?? sni,
        fingerprint: params['fp'],
        alpns: params['alpn'],
        publicKey: null,
        shortId: null,
        spiderX: null,
      );
    }
  }

  late final Uri uri;
  late final String method;
  late final String password;

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => {
        'tag': 'proxy',
        'protocol': 'shadowsocks',
        'settings': {
          'servers': [
            {
              'address': address,
              'method': method,
              'password': password,
              'port': port,
              'level': level,
            }
          ],
        },
        'streamSettings': streamSetting,
        'mux': {'enabled': false, 'concurrency': 8},
      };
}
