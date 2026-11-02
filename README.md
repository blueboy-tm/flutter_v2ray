# flutter_v2ray

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
![](https://img.shields.io/github/license/blueboy-tm/flutter_v2ray)
![](https://img.shields.io/github/stars/blueboy-tm/flutter_v2ray) ![](https://img.shields.io/github/forks/blueboy-tm/flutter_v2ray) ![](https://img.shields.io/github/tag/blueboy-tm/flutter_v2ray) ![](https://img.shields.io/github/release/blueboy-tm/flutter_v2ray) ![](https://img.shields.io/github/issues/blueboy-tm/flutter_v2ray)


## Table of contents
+ [Change logs](#change-logs)
+ [Features](#features)
+ [Supported Platforms](#supported-platforms)
+ [Get started](#get-started)
    * [Add dependency](#add-dependency)
    * [Examples](#examples)
        * [URL Parser](#url-parser)
        * [Multi-Outbound Configuration](#multi-outbound-configuration-modernization)
        * [Edit Configuration](#edit-configuration)
        * [Making V2Ray connection](#making-v2ray-connection)
        * [Bypass LAN Traffic](#bypass-lan-traffic)
        * [More](#more-examples)
+ [Credits](#credits)
+ [Donation](#donation)


## Change logs

> **Release candidate:** The `modernization` branch contains the upcoming
> `2.0.0` release with Android Xray `v26.10.17`. Until `2.0.0` is published
> to pub.dev, `flutter pub add flutter_v2ray` installs the **published**
> version, which may not include the new APIs below.

### 2.0.0 (unreleased)

- Updated Android Xray binding and Android service lifecycle.
- Added multi-outbound builder, routing, balancers and parser fixes.
- Declared Android-only support; see [migration notes](./CHANGELOG.md).

### 1.0.10

- Published Xray core version: 25.3.6

#### [see more](./CHANGELOG.md)

## Features
- Run V2Ray Proxy & VPN Mode
- Get Server Delay
- Parsing V2Ray sharing links and making changes to them
- Composing several Xray outbounds, balancers, DNS and routing settings with the [Dart configuration builder](./doc/config_builder.md) (`modernization` branch)

<br>

## Supported Platforms

| Platform  | Status    | Info |
| --------- | --------- | ---- |
| Android   | Implemented ✅ | Xray v26.10.17 in `modernization` |
| iOS       | Not implemented | Existing Swift code is a registration stub |
| Desktop   | Not implemented | No desktop plugin implementation in this repository |

<br>

## Get started

### Add dependency

You can use the command to add flutter_v2ray as a dependency with the latest stable version:

```console
$ flutter pub add flutter_v2ray
```

Or you can manually add flutter_v2ray into the dependencies section in your pubspec.yaml:

```yaml
dependencies:
  flutter_v2ray: ^replace-with-latest-version
```

To try the unreleased **`modernization`** API (including the multi-outbound builder), use the Git branch instead of the published package:

```yaml
dependencies:
  flutter_v2ray:
    git:
      url: https://github.com/blueboy-tm/flutter_v2ray.git
      ref: modernization
```

Then run `flutter pub get`. The builder described below is **not included in pub.dev version `1.0.10`**.

<br>

## Examples


### URL Parser

``` dart
import 'package:flutter_v2ray/flutter_v2ray.dart';

// v2ray share link like vmess://, vless://, ...
String link = "link_here";
V2RayURL parser = FlutterV2ray.parseFromURL(link);

// Remark of the v2ray
print(parser.remark);

// generate full v2ray configuration (json)
print(parser.getFullConfiguration());
```
### Multi-Outbound Configuration (modernization)

`V2RayConfigBuilder` lets you combine share links into a **single Xray JSON configuration**, choose an outbound with routing rules, configure a balancer, and customize DNS or other Xray sections. The original `FlutterV2ray.parseFromURL()`, `V2RayURL`, and `getFullConfiguration()` APIs still work.

The examples below require the `modernization` Git dependency shown above. Use your own share links instead of the placeholders.

#### 1. Combine two servers and select an outbound

```dart
import 'package:flutter_v2ray/flutter_v2ray.dart';

final first = FlutterV2ray.parseFromURL('vless://YOUR_FIRST_SERVER');
final second = FlutterV2ray.parseFromURL('vless://YOUR_SECOND_SERVER');

final builder = V2RayConfigBuilder.fromUrls(
  [first, second],
  tags: ['server-a', 'server-b'],
)
  // Send incoming SOCKS traffic to server-b instead of the default server-a.
  ..route(inboundTags: ['in_proxy'], outboundTag: 'server-b');

final String xrayJson = builder.buildJson();
```

The `tags` identify outbounds inside Xray. They **must be unique**. With no matching routing rule, Xray uses the first outbound by default; `fromUrls()` also preserves the `direct` and `blackhole` outbounds from the first parsed link.

#### 2. Round Robin: distribute new connections across outbounds

```dart
final builder = V2RayConfigBuilder.fromUrls(
  [
    FlutterV2ray.parseFromURL(firstLink),
    FlutterV2ray.parseFromURL(secondLink),
  ],
  tags: ['server-a', 'server-b'],
)
  ..addBalancer(
    tag: 'auto',
    selector: ['server-'], // Matches outbound tag prefixes.
    strategy: 'roundRobin',
  )
  ..route(
    inboundTags: ['in_proxy'],
    balancerTag: 'auto',
  );

final String xrayJson = builder.buildJson();
```

A balancer **does not select itself**: the `route(... balancerTag: 'auto')` rule is what sends matching traffic to it. `roundRobin` selects among matching outbounds for new connections; it does **not** guarantee automatic failover when a server stops working. Strategies such as `leastLoad` need additional Xray health-check/observatory configuration and separate testing.

#### 3. Customize DNS and routing

```dart
final builder = V2RayConfigBuilder.fromUrls(
  [
    FlutterV2ray.parseFromURL(firstLink),
    FlutterV2ray.parseFromURL(secondLink),
  ],
  tags: ['server-a', 'server-b'],
)
  ..setDnsServers(['1.1.1.1', '8.8.8.8'])
  // More specific rules go before general catch-all rules.
  ..route(
    domains: ['domain:example.com'],
    outboundTag: 'server-b',
  )
  ..route(
    inboundTags: ['in_proxy'],
    outboundTag: 'server-a',
  );

final String xrayJson = builder.buildJson(indent: 2);
```

For arbitrary Xray rules, use `addRoutingRule({...})`. To preserve and modify an existing complete configuration, use `V2RayConfigBuilder.fromJson(existingJson)`:

```dart
final builder = V2RayConfigBuilder.fromJson(existingXrayJson)
  ..addOutboundFromUrl(
    FlutterV2ray.parseFromURL(extraLink),
    tag: 'backup',
  )
  ..setSection('log', {'loglevel': 'info'});

// Or replace a particular outbound while keeping its tag:
// builder.replaceOutbound('backup', customOutboundMap);

final Map<String, dynamic> configMap = builder.build();
final String xrayJson = builder.buildJson();
```

`build()` returns a separate, editable map. `setSection()` replaces a **whole top-level Xray section**; don't use it when you only intend to change one nested field. The native Xray core validates the final configuration, so custom rules and strategies must follow its schema.

#### 4. Connect using the generated JSON

Use the same `FlutterV2ray` API as for single-server configurations:

```dart
final client = FlutterV2ray(
  onStatusChanged: (status) => print(status.state),
);

await client.initializeV2Ray();

if (await client.requestPermission()) {
  await client.startV2Ray(
    remark: 'Multi Server',
    config: xrayJson, // From any of the builders above.
    proxyOnly: false, // true to run only the local proxy.
  );
}

// When finished:
// await client.stopV2Ray();
```

`requestPermission()` is for Android VPN mode; Proxy Only does not require VPN permission. The builder produces **one configuration containing multiple outbounds**, not several simultaneous Android VPN services.

#### 5. Generate ready-to-test JSON files (optional)

From the package repository root, put **two share links, one per line**, in a local file such as `nodes.txt` (do not commit it). Then run:

```bash
dart run tool/multi_outbound_smoke.dart nodes.txt
```

The CLI tool creates `build/multi_outbound_smoke/server-a.json`, `server-b.json`, and `round-robin.json`. Paste each JSON into the example app separately to check individual servers and multi-outbound routing. These files contain server credentials: **do not publish or attach them to issues**. Successful connections alone don't prove both outbounds were selected; use Xray routing logs when validating distribution.

For additional APIs and advanced balancer examples, see the [configuration builder guide](./doc/config_builder.md).

### Edit Configuration
``` dart
// Change v2ray listening port
parser.inbound['port'] = 10890;
// Change v2ray listening host
parser.inbound['listen'] = '0.0.0.0';
// Change v2ray log level
parser.log['loglevel'] = 'info';
// Change v2ray dns
parser.dns = {
    "servers": ["1.1.1.1"]
};
// and ...

// generate configuration with new settings
parser.getFullConfiguration()
```

<br>

### Making V2Ray connection
``` dart
import 'package:flutter_v2ray/flutter_v2ray.dart';

final FlutterV2ray flutterV2ray = FlutterV2ray(
    onStatusChanged: (status) {
        // do something
    },
);

// You must initialize V2Ray before using it.
await flutterV2ray.initializeV2Ray();



// v2ray share link like vmess://, vless://, ...
String link = "link_here";
V2RayURL parser = FlutterV2ray.parseFromURL(link);


// Get Server Delay
print('${flutterV2ray.getServerDelay(config: parser.getFullConfiguration())}ms');

// Permission is not required if you using proxy only
if (await flutterV2ray.requestPermission()){
    flutterV2ray.startV2Ray(
        remark: parser.remark,
        // The use of parser.getFullConfiguration() is not mandatory,
        // and you can enter the desired V2Ray configuration in JSON format
        config: parser.getFullConfiguration(),
        blockedApps: null,
        bypassSubnets: null,
        proxyOnly: false,
    );
}

// Disconnect
flutterV2ray.stopV2Ray();
```

<br>


### Bypass LAN Traffic
```dart
final List<String> subnets = [
    "0.0.0.0/5",
    "8.0.0.0/7",
    "11.0.0.0/8",
    "12.0.0.0/6",
    "16.0.0.0/4",
    "32.0.0.0/3",
    "64.0.0.0/2",
    "128.0.0.0/3",
    "160.0.0.0/5",
    "168.0.0.0/6",
    "172.0.0.0/12",
    "172.32.0.0/11",
    "172.64.0.0/10",
    "172.128.0.0/9",
    "173.0.0.0/8",
    "174.0.0.0/7",
    "176.0.0.0/4",
    "192.0.0.0/9",
    "192.128.0.0/11",
    "192.160.0.0/13",
    "192.169.0.0/16",
    "192.170.0.0/15",
    "192.172.0.0/14",
    "192.176.0.0/12",
    "192.192.0.0/10",
    "193.0.0.0/8",
    "194.0.0.0/7",
    "196.0.0.0/6",
    "200.0.0.0/5",
    "208.0.0.0/4",
    "240.0.0.0/4",
];

flutterV2ray.startV2Ray(
    remark: parser.remark,
    config: parser.getFullConfiguration(),
    blockedApps: null,
    bypassSubnets: subnets,
    proxyOnly: false,
);
```

<br>


## Android integration and release requirements

This plugin currently supports **Android only**. The bundled native
`tun2socks` executable is started from `ApplicationInfo.nativeLibraryDir`
using `ProcessBuilder`. It therefore **must be extracted to a file**, rather
than stored only inside the APK.

### Host app packaging

In the host application's `android/app/build.gradle.kts`:

```kotlin
android {
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
```

For a Groovy `build.gradle` host app, use:

```groovy
android {
    packaging {
        jniLibs {
            useLegacyPackaging true
        }
    }
}
```

Do **not** copy the previous README's `abiFilters`, APK splits or
`android.bundle.enableUncompressedNativeLibs = false` instructions blindly.
Those were tied to older Android packaging practices and aren't required
just to enable the plugin. Keep the ABIs your app actually supports, and
check device compatibility with the release artifact.

### 16 KB page-size compatibility

The updated 64-bit native libraries have been checked on the Android example
for 16 KB ELF segment alignment and compatible APK packaging; however,
**your final app bundle and every bundled native library** must still be
verified separately.

A successful `flutter build appbundle --release` followed by the Android
bundletool alignment metadata check is recommended. For APKs, check with the
Android SDK `zipalign` utility (where applicable):

```bash
zipalign -c -P 16 -v 4 path/to/app-release.apk
```

`useLegacyPackaging = true` intentionally extracts native libraries;
ZIP alignment alone is not a substitute for checking the alignment of their
ELF `LOAD` segments. Do not assume third-party app dependencies are
16 KB compatible just because this plugin's native binaries are.

### Foreground services, notifications and Google Play

The Android manifest includes a foreground service for the VPN/proxy daemon
and declares `FOREGROUND_SERVICE_SPECIAL_USE` on Android 14+. Apps
published through Google Play may need to declare and justify foreground
service use in Play Console. App approval is **not** guaranteed by a
successful local build. Preserve the relevant merged manifest permissions
and VPN-service declaration.

For full implementation details, see
[the example Android configuration](./example/android/app/build.gradle.kts)
and the [2.0.0 change log](./CHANGELOG.md).

<br>


## More examples
- [Simple v2ray client written in flutter](https://github.com/blueboy-tm/flutter_v2ray/blob/modernization/example/lib/main.dart)

## Credits
[badvpn (tun2socks)](https://github.com/ambrop72/badvpn) Copyright (C) Ambroz Bizjak

All rights reserved.


## Donation
If you liked this package, you can support me with one of the following links.

### Buy me a coffee

<a href="https://www.buymeacoffee.com/bBUqA54Bhe" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>


### Cryptocurrency

+ BTC:
    * bc1qrtq0ygmxw7meak3ukvxn03za2j7t7s4uxuujct
+ Tron
    * TVQQdim3pxa4XoZyRRVHQ8GsY42rEgB4ow
+ USDT
    * TRC20
        * TVQQdim3pxa4XoZyRRVHQ8GsY42rEgB4ow
    * ERC20
        * 0xD5d931BB40F02Ed45172faebD805B3f0ba70Fe73
+ DogeCoin
    * DNFaHFzmUfeUB6NFgQX1sLn9q8kknTmKd8

