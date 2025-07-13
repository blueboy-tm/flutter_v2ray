import Flutter
import LibXray
import NetworkExtension
import UIKit

public class FlutterV2rayPlugin: NSObject, FlutterPlugin {
    // 静态共享的事件流实例
    public static var sharedEventSink: FlutterEventSink?

    // V2Ray 控制器的单例实例
    private lazy var controller: V2rayController = .shared()
    // V2Ray 核心管理器的单例实例
    private lazy var coreManager: V2rayCoreManager = .shared()
    private lazy var vpnConifg: VPNConfigValidator = .shared()

    private static var sharedFlutterV2rayPlugin: FlutterV2rayPlugin = .init()

    public class func shared() -> FlutterV2rayPlugin {
        return sharedFlutterV2rayPlugin
    }

    // 注册插件到 Flutter 引擎
    public static func register(with registrar: FlutterPluginRegistrar) {
        // 定义方法通道和事件通道，用于与 Flutter 通信
        let methodChannel = FlutterMethodChannel(name: "flutter_v2ray", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_v2ray/status", binaryMessenger: registrar.messenger())

        let instance = FlutterV2rayPlugin()
        // 将插件实例设置为方法通道的处理代理
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        // 将插件实例设置为事件通道的流处理器
        eventChannel.setStreamHandler(instance)
    }

    // 方法调用处理器的映射表，用于映射方法名到具体处理函数
    private lazy var methodHandlers: [String: (FlutterMethodCall, @escaping FlutterResult) -> Void] = [
        "startV2Ray": handleStartV2Ray, // 启动 V2Ray
        "stopV2Ray": handleStopV2Ray, // 停止 V2Ray
        "initializeV2Ray": handleInitializeV2Ray, // 初始化 V2Ray
        "getServerDelay": handleGetServerDelay, // 获取服务器延迟
        "getConnectedServerDelay": handleGetConnectedServerDelay, // 获取已连接服务器的延迟
        "requestPermission": handleRequestPermission, // 请求 VPN 权限
        "getCoreVersion": handleGetCoreVersion, // 获取核心版本号
        "checkVPNState": handleCheckVPNState, // 检查VPN
    ]

    // 主方法调用处理函数，匹配方法名并调用相应的处理器
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let handler = methodHandlers[call.method] {
            handler(call, result)
        } else {
            result(FlutterMethodNotImplemented) // 方法未实现
        }
    }

    // 处理启动 V2Ray 的方法
    private func handleStartV2Ray(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // 从方法调用参数中解析必需数据
        guard let args = call.arguments as? [String: Any],
              let remark = args["remark"] as? String,
              let config = args["config"] as? String
        else {
            // 参数缺失或无效时返回错误
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "启动 V2Ray 的参数缺失或无效", details: nil))
            return
        }
        // 获取可选参数
        let blockedApps = args["blocked_apps"] as? [String] ?? []
        let bypassSubnets = args["bypass_subnets"] as? [String] ?? []
        let proxyOnly = args["proxyOnly"] as? Bool ?? false

        // 调用控制器方法启动 V2Ray
        controller.startV2Ray(remark: remark, config: config, blockedApps: blockedApps, bypassSubnets: bypassSubnets, proxyOnly: proxyOnly, result: result)
    }

    // 处理停止 V2Ray 的方法
    private func handleStopV2Ray(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        controller.stopV2Ray(result: result)
    }

    /// 处理 handleInitializeV2Ray
    private func handleInitializeV2Ray(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        controller.initializeV2Ray(result: result)
    }

    /// 发送给Flutter消息
    public func sendEventToFlutter(_ message: Any) {
        if let eventSink = FlutterV2rayPlugin.sharedEventSink {
            DispatchQueue.main.async {
                eventSink(message) // 确保在主线程中发送事件
            }
        }
    }

    // 获取服务器延迟
    private func handleGetServerDelay(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let config = args["config"] as? String,
              let url = args["url"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "获取服务器延迟的参数缺失或无效", details: nil))
            return
        }
        getServerDelay(config: config, url: url, result: result)
    }

    // 获取已连接服务器的延迟
    private func handleGetConnectedServerDelay(_ call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let url = args["url"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "获取已连接服务器延迟的参数缺失或无效", details: nil))
            return
        }
        getConnectedServerDelay(url: url, result: result)
    }

    // 请求 VPN 权限
    private func handleRequestPermission(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(true);
    }

    // 获取核心版本号
    private func handleGetCoreVersion(_ call: FlutterMethodCall, result: FlutterResult) {
        let baseVersion = LibXrayXrayVersion()
        // Call the function
        if let jsonObject = Utilities.decodeBase64AndParseJSON(baseVersion) {
            // Access individual keys in the JSON object
            if let data = jsonObject["data"] as? String {
                result("v\(data)")
            }
        } else {
            result(nil)
        }
    }

    // 检查VPN
    private func handleCheckVPNState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        vpnConifg.checkInitialState { isValid in
            if isValid == true {
//                print("isValid \(isValid)")
                // 获取 V2RAY_STATE 的字符串表示
                
                let connectStatus = AppConfigs.V2RAY_STATES.CONNECTED.description
                let stats = V2RayStats.defaultStats()

                self.sendEventToFlutter([
                    stats.time,
                    stats.uploadSpeed,
                    stats.downloadSpeed,
                    stats.totalUpload,
                    stats.totalDownload,
                    connectStatus, // 当前状态
                ])
            } else {
                self.controller.stopV2Ray(result: result)
            }
        }
    }

    // 获取服务器延迟
    private func getServerDelay(config: String, url: String, result: FlutterResult) {
        let delay = 100 // 示例延迟
        result(delay)
    }

    // 获取已连接服务器延迟
    private func getConnectedServerDelay(url: String, result: FlutterResult) {
        let delay = 50 // 示例延迟
        result(delay)
    }

    // 处理 Flutter 错误
    private func handleFlutterError(result: @escaping FlutterResult, code: String, message: String, details: String?) {
        result(FlutterError(
            code: code,
            message: message,
            details: details
        ))
    }
}

extension FlutterV2rayPlugin: FlutterStreamHandler {
    // 监听 Flutter 事件通道
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        FlutterV2rayPlugin.sharedEventSink = events
        return nil
    }

    // 停止监听 Flutter 事件通道
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        FlutterV2rayPlugin.sharedEventSink = nil
        return nil
    }
}
