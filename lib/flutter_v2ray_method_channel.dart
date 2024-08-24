import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'model/v2ray_status.dart' show V2RayStatus;

import 'flutter_v2ray_platform_interface.dart';

/// An implementation of [FlutterV2rayPlatform] that uses method channels.
class MethodChannelFlutterV2ray extends FlutterV2rayPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_v2ray');
  final eventChannel = const EventChannel('flutter_v2ray/status');

  @override
  Future<void> initializeV2Ray({
    required void Function(V2RayStatus status) onStatusChanged,
  }) async {
    eventChannel.receiveBroadcastStream().distinct().cast().listen((event) {
      if (event != null) {
        onStatusChanged.call(V2RayStatus(
          duration: event[0],
          uploadSpeed: double.parse(event[1]).toInt(),
          downloadSpeed: double.parse(event[2]).toInt(),
          upload: double.parse(event[3]).toInt(),
          download: double.parse(event[4]).toInt(),
          state: event[5],
        ));
      }
    });
    await methodChannel.invokeMethod(
      'initializeV2Ray',
    );
  }

  @override
  Future<void> startV2Ray({
    required String remark,
    required String config,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    bool proxyOnly = false,
  }) async {
    await methodChannel.invokeMethod('startV2Ray', {
      "remark": remark,
      "config": config,
      "blocked_apps": blockedApps,
      "bypass_subnets": bypassSubnets,
      "proxy_only": proxyOnly,
    });
  }

  @override
  Future<void> stopV2Ray() async {
    await methodChannel.invokeMethod('stopV2Ray');
  }

  @override
  Future<int> getServerDelay({required String config}) async {
    return await methodChannel.invokeMethod('getServerDelay', {
      "config": config,
    });
  }

  @override
  Future<int> getConnectedServerDelay() async {
    return await methodChannel.invokeMethod('getConnectedServerDelay');
  }

  @override
  Future<bool> requestPermission() async {
    return (await methodChannel.invokeMethod('requestPermission')) ?? false;
  }

  @override
  Future<String> getCoreVersion() async {
    return await methodChannel.invokeMethod('getCoreVersion');
  }
}
