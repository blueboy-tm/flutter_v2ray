import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';

void main() {
  const firstLink =
      'vless://11111111-1111-4111-8111-111111111111@first.example:443'
      '?security=tls&type=ws&host=front.example&sni=front.example';
  const secondLink =
      'vless://22222222-2222-4222-8222-222222222222@second.example:443'
      '?security=tls&type=ws&path=%2Fsocket';

  test('WebSocket default path stays a string', () {
    final parsed = FlutterV2ray.parseFromURL(firstLink);
    final settings = parsed.outbound1['streamSettings'] as Map;
    expect((settings['wsSettings'] as Map)['path'], '/');
    expect((settings['tlsSettings'] as Map)['serverName'], 'front.example');
    expect(settings.containsKey('realitySettings'), isTrue);
    expect(settings['realitySettings'], isNull);
  });

  test('REALITY uses new Xray client key without TLS-only fields', () {
    final parsed = FlutterV2ray.parseFromURL(
      'vless://11111111-1111-4111-8111-111111111111@reality.example:443'
      '?security=reality&type=tcp&pbk=publicValue&sid=aabb&fp=chrome&sni=front.example',
    );
    final stream = parsed.outbound1['streamSettings'] as Map;
    final reality = stream['realitySettings'] as Map;
    expect(reality['password'], 'publicValue');
    expect(reality.containsKey('publicKey'), isFalse);
    expect(reality['shortId'], 'aabb');
    expect(stream['tlsSettings'], isNull);
  });

  test('compose multiple link outbounds with round-robin routing', () {
    final builder =
        V2RayConfigBuilder.fromUrl(FlutterV2ray.parseFromURL(firstLink))
          ..addOutboundFromUrl(
            FlutterV2ray.parseFromURL(secondLink),
            tag: 'proxy-backup',
          )
          ..addBalancer(
            tag: 'auto',
            selector: ['proxy'],
            strategy: 'roundRobin',
          )
          ..route(
            inboundTags: ['in_proxy'],
            balancerTag: 'auto',
          )
          ..setDnsServers(['1.1.1.1', 'https://dns.google/dns-query']);

    final data = builder.build();
    expect((data['outbounds'] as List), hasLength(4));
    expect((data['outbounds'] as List)[0]['tag'], 'proxy');
    expect((data['outbounds'] as List)[3]['tag'], 'proxy-backup');
    final routing = data['routing'] as Map;
    expect((routing['balancers'] as List).single['strategy']['type'],
        'roundRobin');
    expect((routing['rules'] as List).single['balancerTag'], 'auto');
    expect((data['dns'] as Map)['servers'], hasLength(2));
    expect(jsonDecode(builder.buildJson()), equals(builder.build()));

    // Returned objects must not be able to mutate the builder state.
    (data['outbounds'] as List).clear();
    expect((builder.build()['outbounds'] as List), hasLength(4));
  });

  test('preserve nonstandard full Xray config sections', () {
    final builder = V2RayConfigBuilder.fromJson(jsonEncode({
      'inbounds': [
        {'tag': 'local', 'protocol': 'socks', 'port': 1080}
      ],
      'outbounds': [
        {'tag': 'one', 'protocol': 'freedom'}
      ],
      'burstObservatory': {
        'subjectSelector': ['one'],
        'pingConfig': {'destination': 'https://example.com'}
      },
      'customFutureField': {'keep': true},
    }));
    builder
      ..addBalancer(tag: 'fastest', selector: ['one'],
          strategy: 'leastLoad')
      ..route(domains: ['domain:example.com'], balancerTag: 'fastest');
    final result = builder.build();
    expect(result['customFutureField']['keep'], isTrue);
    expect(result['burstObservatory']['subjectSelector'], ['one']);
  });

  test('reject duplicate tags and invalid route targets', () {
    final builder =
        V2RayConfigBuilder.fromUrl(FlutterV2ray.parseFromURL(firstLink));
    expect(
      () => builder.addOutboundFromUrl(
          FlutterV2ray.parseFromURL(secondLink), tag: 'proxy'),
      throwsArgumentError,
    );
    expect(() => builder.route(domains: ['domain:example.com']),
        throwsArgumentError);
    expect(() => V2RayConfigBuilder.empty().build(), throwsStateError);
    expect(() => V2RayConfigBuilder.fromJson('[]'), throwsFormatException);
  });

  test('SIP002 Shadowsocks credentials support Base64URL', () {
    final credentials =
        base64Url.encode(utf8.encode('aes-128-gcm:pass:with:colons'));
    final url = FlutterV2ray.parseFromURL(
        'ss://$credentials@proxy.example:8388#test');
    final server =
        (url.outbound1['settings']['servers'] as List).first as Map;
    expect(server['method'], 'aes-128-gcm');
    expect(server['password'], 'pass:with:colons');
  });

  test('plain Shadowsocks and SOCKS credentials are parsed', () {
    final ss = FlutterV2ray.parseFromURL(
        'ss://aes-256-gcm:secret@proxy.example:8388');
    expect(ss.outbound1['settings']['servers'][0]['method'],
        'aes-256-gcm');
    final socks = FlutterV2ray.parseFromURL(
        'socks://alice:secret@proxy.example:1080');
    expect(socks.outbound1['settings']['servers'][0]['users'][0]['user'],
        'alice');
  });

  test('VMess parser accepts Base64URL share links', () {
    final raw = jsonEncode({
      'add': 'vmess.example',
      'port': '443',
      'id': '11111111-1111-4111-8111-111111111111',
      'ps': 'Sample',
      'net': 'ws',
      'path': '/app',
      'host': 'front.example',
      'tls': 'tls',
      'sni': 'tls.example',
    });
    final share = 'vmess://${base64Url.encode(utf8.encode(raw))}';
    final parsed = FlutterV2ray.parseFromURL(share);
    expect(parsed.address, 'vmess.example');
    expect(parsed.remark, 'Sample');
    expect(parsed.outbound1['streamSettings']['tlsSettings']['serverName'],
        'tls.example');
  });
}
