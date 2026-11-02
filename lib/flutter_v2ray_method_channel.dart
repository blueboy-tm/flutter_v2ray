import 'dart:async';

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

  StreamSubscription<dynamic>? _statusSubscription;

  static int _readCounter(dynamic value) {
    if (value is int) return value;
    return int.parse(value.toString());
  }

  @override
  Future<void> initializeV2Ray({
    required void Function(V2RayStatus status) onStatusChanged,
    required String notificationIconResourceType,
    required String notificationIconResourceName,
  }) async {
    // Re-initialization must not leave multiple event listeners behind.
    await _statusSubscription?.cancel();
    _statusSubscription = eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        try {
          if (event is! List || event.length != 6) {
            throw const FormatException('Invalid V2Ray status event');
          }
          onStatusChanged(V2RayStatus(
            duration: event[0].toString(),
            uploadSpeed: _readCounter(event[1]),
            downloadSpeed: _readCounter(event[2]),
            upload: _readCounter(event[3]),
            download: _readCounter(event[4]),
            state: event[5].toString(),
          ));
        } catch (error, stack) {
          FlutterError.reportError(FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'flutter_v2ray',
            context: ErrorDescription('while processing a V2Ray status event'),
          ));
        }
      },
      onError: (Object error, StackTrace stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'flutter_v2ray',
          context: ErrorDescription('while receiving V2Ray status events'),
        ));
      },
    );
    await methodChannel.invokeMethod(
      'initializeV2Ray',
      {
        "notificationIconResourceType": notificationIconResourceType,
        "notificationIconResourceName": notificationIconResourceName,
      },
    );
  }

  @override
  Future<void> startV2Ray({
    required String remark,
    required String config,
    required String notificationDisconnectButtonName,
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
      "notificationDisconnectButtonName": notificationDisconnectButtonName,
    });
  }

  @override
  Future<void> stopV2Ray() async {
    await methodChannel.invokeMethod('stopV2Ray');
  }

  @override
  Future<int> getServerDelay(
      {required String config, required String url}) async {
    return (await methodChannel.invokeMethod<int>('getServerDelay', {
      "config": config,
      "url": url,
    })) ?? -1;
  }

  @override
  Future<int> getConnectedServerDelay(String url) async {
    return (await methodChannel
        .invokeMethod<int>('getConnectedServerDelay', {"url": url})) ?? -1;
  }

  @override
  Future<bool> requestPermission() async {
    return (await methodChannel.invokeMethod<bool>('requestPermission')) ?? false;
  }

  @override
  Future<String> getCoreVersion() async {
    return (await methodChannel.invokeMethod<String>('getCoreVersion')) ?? 'unknown';
  }
}
