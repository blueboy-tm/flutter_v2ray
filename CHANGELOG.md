## 2.0.0

Major Android modernization release. Existing `FlutterV2ray` connection methods
remain available, but native core, protocol configuration and supported platform
declarations have changed.

### Added
- `V2RayConfigBuilder` to compose multiple Xray outbounds, custom routing rules,
  balancers, DNS servers and arbitrary Xray JSON sections.
- Flutter-independent `parseV2RayURL()` helper for pure-Dart configuration tools.
- Dart parser/builder regression tests and CI checks.

### Changed
- Updated Android native Xray binding to AndroidLibXrayLite
  `v26.10.17`, resolved from the upstream release AAR at build time instead
  of vendoring `libv2ray.aar`.
- Reworked Android VPN and Proxy Only service lifecycle and foreground
  notification startup, including handling of permission denial, reconnection
  and shutdown paths.
- Improved share-link parsing for VMess (Base64URL), Shadowsocks/SIP002,
  SOCKS, VLESS transport settings and Xray TLS/REALITY JSON.
- Updated Android native tun2socks binaries and tested Android 64-bit
  16 KB page compatibility in the example application.
- Improved Dart status event subscription management and input validation.
- Declared **Android only** in Flutter's plugin platform metadata. The
  repository contains an incomplete iOS stub, but no functional iOS VPN API.

### Breaking or behavior-sensitive changes
- Legacy `allowInsecure` and `insecure` link parameters no longer disable
  TLS certificate verification in generated configuration. Import a trusted
  server certificate or use valid TLS settings instead.
- REALITY share-link `pbk` is emitted as the newer Xray client-side
  `realitySettings.password` field.
- On platforms other than Android, `requestPermission()` now throws
  `UnsupportedError` instead of returning `true`.
- Android apps that launch the bundled `tun2socks` executable must retain
  extraction of native libraries (for Gradle Kotlin DSL:
  `packaging { jniLibs { useLegacyPackaging = true } }`).
- iOS is no longer advertised as a supported Flutter plugin platform.

See `README.md` and `doc/config_builder.md` for multi-outbound examples.
The individual outbound, VPN/Proxy Only, and Round Robin smoke configurations
were exercised in the Android example. Smart failover/least-load balancing
and every Xray protocol variation have **not** been exhaustively verified.

## 1.0.10

* update xray core version to 25.3.6

## 1.0.9

* add disconnect button (notificationDisconnectButtonName)
* fix requestPermission
* fix notification bugs  (android 13 and higher)

## 1.0.8

* fix registerReceiver error
* fix build for API 34 ( check IntentFilter V2RAY_CONNECTION_INFO )
* change type of usage statistic
* fix deprecated apis
* update v2ray core to 1.8.17

## 1.0.7

* fix v2rayBroadCastReceiver null exception
* fix #35: registerReceiver error
* update libv2ray to 1.8.7
* fix #43: Adding DNS servers to the VPN service

## 1.0.6

* fix #24 issue: fix notification and background service
* fix #11 issue: add bypassSubnets for bypass lan traffic
* add getConnectedServerDelay
* add getCoreVersion
* optimize java codes

## 1.0.5

* fix #10 issue: notification service

## 1.0.4

* fix getServerDelay

## 1.0.3

* fix vless fingerprint 
* update android XRay version

## 1.0.2

* fix #4 issue: tlsSettings -> path
* fix #7 issue: reset total traffic after disconnect 
* validate json config

## 1.0.1

* fix EventChannel crash
* add getServerDelay method

## 1.0.0

* implement v2ray for android
* create v2ray share link parser
