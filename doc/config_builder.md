# Dart configuration composer (modernization)

The legacy `FlutterV2ray.parseFromURL(link).getFullConfiguration()` remains
available. For multiple servers, routing and custom Xray options, use
`V2RayConfigBuilder`, exported by `package:flutter_v2ray/flutter_v2ray.dart`.

## Multiple outbounds and a round-robin balancer

```dart
import 'package:flutter_v2ray/flutter_v2ray.dart';

final config = V2RayConfigBuilder.fromUrls([
  FlutterV2ray.parseFromURL(primaryLink),
  FlutterV2ray.parseFromURL(backupLink),
], tags: ['server-a', 'server-b'])
  ..addBalancer(
    tag: 'auto',
    selector: ['server-'], // Xray selectors match outbound-tag prefixes
    strategy: 'roundRobin',
  )
  ..route(inboundTags: ['in_proxy'], balancerTag: 'auto')
  ..setDnsServers([
    '1.1.1.1',
    'https://dns.google/dns-query',
  ]);

await flutterV2ray.startV2Ray(
  remark: 'Auto routing',
  config: config.buildJson(),
);
```

The first outbound is the default in Xray unless your routing rules
select another outbound or balancer. The generated config also contains the
legacy `direct` and `blackhole` outbounds. Tags must be unique.

## Custom sections, least-load or external JSON

```dart
final builder = V2RayConfigBuilder.fromJson(existingXrayJson)
  ..addOutboundFromUrl(
    FlutterV2ray.parseFromURL(extraShareLink),
    tag: 'backup',
  )
  ..addBalancer(
    tag: 'best',
    selector: ['proxy', 'backup'],
    strategy: 'leastLoad',
  )
  ..setSection('burstObservatory', {
    'subjectSelector': ['proxy', 'backup'],
    'pingConfig': {'destination': 'https://www.google.com/generate_204'},
  })
  ..addRoutingRule({
    'type': 'field',
    'domain': ['domain:example.com'],
    'balancerTag': 'best',
  });

final Map<String, dynamic> editableCopy = builder.build();
final String finalConfig = builder.buildJson(indent: 2);
```

The builder preserves unknown top-level sections from existing JSON and
returns **copies**, so external edits do not mutate the builder.
`setSection(name, value)` replaces one complete Xray top-level section.
`addOutbound`, `replaceOutbound`, `addRoutingRule`, `route`,
`setDnsServers` and `addBalancer` provide more focused changes.

This is a **composer**, not an independent implementation of the full Xray
configuration schema. The embedded native core validates the final config.
Balancer strategies such as `leastLoad` require compatible core settings;
a name or selector alone does not guarantee independent failover.
For full control over `inbounds`, `dns`, `routing`, `policy` and other
options you may still pass raw JSON to `startV2Ray`. Note that the Android
native adapter may manage the `policy` and `stats` sections when traffic
statistics are enabled.

## Compatibility and security notes

- The existing `FlutterV2ray` methods and `V2RayURL` link classes remain.
- Generated TLS configs keep certificate verification enabled; the obsolete
  `allowInsecure` share-link flag is not used to disable it.
- REALITY share-link `pbk` maps to Xray's newer client-side
  `realitySettings.password` field.
- Only Android functionality has been implemented; iOS remains a stub.
- Do not include actual UUIDs, credentials or secret URLs in public issue logs.
