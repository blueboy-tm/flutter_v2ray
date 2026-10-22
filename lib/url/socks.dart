import 'dart:convert';

import 'package:flutter_v2ray/url/url.dart';

class SocksURL extends V2RayURL {
  SocksURL({required super.url}) {
    if (!url.startsWith('socks://')) {
      throw ArgumentError('url is invalid');
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty) {
      throw ArgumentError('url is invalid');
    }
    uri = parsed;
    var credentials = uri.userInfo;
    if (credentials.isEmpty) {
      username = null;
      password = null;
    } else {
      if (!credentials.contains(':')) {
        try {
          credentials =
              utf8.decode(base64Decode(base64.normalize(credentials)));
        } catch (_) {
          throw ArgumentError('Invalid SOCKS credentials');
        }
      }
      final splitAt = credentials.indexOf(':');
      if (splitAt < 0) throw ArgumentError('Invalid SOCKS credentials');
      username = Uri.decodeComponent(credentials.substring(0, splitAt));
      password = Uri.decodeComponent(credentials.substring(splitAt + 1));
    }
  }

  late final String? username;
  late final String? password;
  late final Uri uri;

  @override
  String get address => uri.host;

  @override
  int get port => uri.hasPort ? uri.port : super.port;

  @override
  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  @override
  Map<String, dynamic> get outbound1 => {
        'tag': 'proxy',
        'protocol': 'socks',
        'settings': {
          'servers': [
            {
              'address': address,
              'port': port,
              if (username != null)
                'users': [
                  {'user': username, 'pass': password, 'level': level}
                ],
            }
          ],
        },
        'streamSettings': streamSetting,
        'mux': {'enabled': false, 'concurrency': 8},
      };
}
