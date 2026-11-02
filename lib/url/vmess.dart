import 'dart:convert';

import 'package:flutter_v2ray/url/url.dart';

class VmessURL extends V2RayURL {
  VmessURL({required super.url}) {
    if (!url.startsWith('vmess://')) {
      throw ArgumentError('url is invalid');
    }
    var raw = url.substring(8).trim();
    try {
      raw = base64.normalize(raw);
      final decoded = jsonDecode(utf8.decode(base64Decode(raw)));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('VMess payload is not an object');
      }
      rawConfig = decoded;
    } catch (_) {
      throw ArgumentError('url is invalid');
    }
    var sni = super.populateTransportSettings(
      transport: rawConfig['net']?.toString() ?? 'tcp',
      headerType: rawConfig['type']?.toString(),
      host: rawConfig['host']?.toString(),
      path: rawConfig['path']?.toString(),
      seed: rawConfig['path']?.toString(),
      quicSecurity: rawConfig['host']?.toString(),
      key: rawConfig['path']?.toString(),
      mode: rawConfig['type']?.toString(),
      serviceName: rawConfig['path']?.toString(),
    );
    String? fingerprint = (rawConfig['fp'] != null && rawConfig['fp'] != '')
        ? rawConfig['fp'].toString()
        : streamSetting['tlsSettings']?['fingerprint'];
    super.populateTlsSettings(
      streamSecurity: rawConfig['tls']?.toString(),
      allowInsecure: allowInsecure,
      sni: rawConfig['sni']?.toString().isNotEmpty == true
          ? rawConfig['sni'].toString()
          : sni,
      fingerprint: fingerprint,
      alpns: rawConfig['alpn']?.toString(),
      publicKey: null,
      shortId: null,
      spiderX: null,
    );
  }
  late final Map<String, dynamic> rawConfig;

  @override
  String get remark => rawConfig['ps']?.toString() ?? '';

  @override
  String get address => rawConfig['add']?.toString() ?? '';

  @override
  int get port => int.tryParse(rawConfig['port'].toString()) ?? super.port;

  @override
  Map<String, dynamic> get outbound1 => {
        "tag": "proxy",
        "protocol": "vmess",
        "settings": {
          "vnext": [
            {
              "address": address,
              "port": port,
              "users": [
                {
                  "id": rawConfig['id'] ?? '',
                  "alterId": int.tryParse(rawConfig['aid'].toString()) ?? 0,
                  "security": (rawConfig['scy']?.toString().isEmpty ?? true)
                      ? security
                      : rawConfig['scy'].toString(),
                  "level": level,
                  "encryption": "",
                  "flow": ""
                }
              ]
            }
          ],
          "servers": null,
          "response": null,
          "network": null,
          "address": null,
          "port": null,
          "domainStrategy": null,
          "redirect": null,
          "userLevel": null,
          "inboundTag": null,
          "secretKey": null,
          "peers": null
        },
        "streamSettings": streamSetting,
        "proxySettings": null,
        "sendThrough": null,
        "mux": {
          "enabled": false,
          "concurrency": 8,
        }
      };
}
