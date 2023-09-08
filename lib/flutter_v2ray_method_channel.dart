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
      onStatusChanged.call(V2RayStatus(
        duration: event[0],
        uploadSpeed: event[1],
        downloadSpeed: event[2],
        upload: event[3],
        download: event[4],
        state: event[5],
      ));
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
    bool proxyOnly = false,
  }) async {
    await methodChannel.invokeMethod('startV2Ray', {
      "remark": remark,
      "config": config,
      "blocked_apps": blockedApps,
      "proxy_only": proxyOnly,
    });
  }

  @override
  Future<void> stopV2Ray() async {
    await methodChannel.invokeMethod('stopV2Ray');
  }

  @override
  Future<bool> requestPermission() async {
    return (await methodChannel.invokeMethod('requestPermission')) ?? false;
  }
}
