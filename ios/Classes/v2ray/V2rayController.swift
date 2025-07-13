import Flutter
import NetworkExtension
import os.log

let conLog = OSLog(subsystem: "com.group.sulian.app", category: "vpn_controller")

public class V2rayController {
    private lazy var pligun = FlutterV2rayPlugin.shared()

    // 单例
    private static var sharedV2rayController: V2rayController = .init()
    public class func shared() -> V2rayController {
        return sharedV2rayController
    }

    // V2ray Core
    private lazy var coreManager: V2rayCoreManager = .shared()
    private var manager = NETunnelProviderManager.shared()

    private lazy var vpnConifg: VPNConfigValidator = .shared()

    private var vpnStatusObserver: NSObjectProtocol?
    deinit {
        // 移除监听
        if let observer = vpnStatusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // 防抖计时器变量
    var debounceTimer: Timer?
    let debounceInterval: TimeInterval = 0.5 // 设置防抖间隔为0.5秒
    var timeoutTimer: Timer? // 新增超时计时器
//    let timeoutInterval: TimeInterval = 5.0 // 设置超时时间为5秒

    // 设置VPN状态监听
    private func setupVPNStatusObserver(result: @escaping FlutterResult) {
        // 先取消所有现有计时器
        debounceTimer?.invalidate()
        timeoutTimer?.invalidate()

        // 设置超时计时器
//        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutInterval, repeats: false) { [weak self] _ in
//            guard let self = self else { return }
//            os_log("VPN状态检测超时", log: conLog, type: .error)
//            self.cleanupObservers()
//            AppConfigs.V2RAY_STATE = .DISCONNECT
//            self.initializeV2Ray(result: result)
//        }

        vpnStatusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // 取消之前的防抖计时器
            debounceTimer?.invalidate()

            // 设置新的防抖计时器
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                os_log("VPN状态变化通知触发", log: conLog, type: .debug)
                self.vpnConifg.checkInitialState { isValid in
                    print("isValid: \(isValid)")
                    if isValid {
                        self.cleanupObservers()
                        AppConfigs.V2RAY_STATE = .CONNECTED
                        self.initializeV2Ray(result: result)
                    } 
                }
            }
        }
    }

    // 清理观察者和计时器
    private func cleanupObservers() {
        if let observer = vpnStatusObserver {
            NotificationCenter.default.removeObserver(observer)
            vpnStatusObserver = nil
        }
        debounceTimer?.invalidate()
        debounceTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    public func initializeV2Ray(result: @escaping FlutterResult) {
        // 获取 V2RAY_STATE 的字符串表示
        let connectStatus = AppConfigs.V2RAY_STATE.description
        let stats = V2RayStats.defaultStats()

        pligun.sendEventToFlutter([
            stats.time,
            stats.uploadSpeed,
            stats.downloadSpeed,
            stats.totalUpload,
            stats.totalDownload,
            connectStatus // 当前状态
        ])

        result(nil)
    }

    // 启动 V2ray
    public func startV2Ray(remark: String, config: String, blockedApps: [String], bypassSubnets: [String], proxyOnly: Bool, result: @escaping FlutterResult) {
        // 首次启动时设置监听
        if vpnStatusObserver == nil {
            setupVPNStatusObserver(result: result)
        }

        coreManager.setUpListener()
        // 打印输入参数，便于调试
//        print("startV2Ray 被调用，传入的参数如下：")
//        print("remark: \(remark)")
//        print("config: \(config)")
//        print("blockedApps: \(blockedApps)")
//        print("bypassSubnets: \(bypassSubnets)")
//        print("proxyOnly: \(proxyOnly)")

        // 解析 V2ray 配置
        guard let v2rayConfig = Utilities.parseV2rayJsonFile(remark: remark, config: config, blockedApplication: blockedApps, bypassSubnets: bypassSubnets) else {
            // 如果解析失败，直接返回
            return
        }

        AppConfigs.V2RAY_CONFIG = v2rayConfig
//        AppConfigs.V2RAY_STATE = .CONNECTED

//        print(AppConfigs.V2RAY_CONFIG?.APPLICATION_ICON ?? 0)
//        print(AppConfigs.V2RAY_CONFIG?.APPLICATION_NAME ?? "Default Name")
//        print(AppConfigs.V2RAY_CONFIG?.BLOCKED_APPS ?? "BLOCKED_APPS")
//        print(AppConfigs.V2RAY_CONFIG?.BYPASS_SUBNETS ?? "BYPASS_SUBNETS")
//        print(AppConfigs.V2RAY_CONFIG?.CONNECTED_V2RAY_SERVER_ADDRESS ?? "Default Address")
//        print(AppConfigs.V2RAY_CONFIG?.CONNECTED_V2RAY_SERVER_PORT ?? "Default Port")
//        print(AppConfigs.V2RAY_CONFIG?.ENABLE_TRAFFIC_STATISTICS ?? false)
//        print(AppConfigs.V2RAY_CONFIG?.LOCAL_HTTP_PORT ?? 0)
//        print(AppConfigs.V2RAY_CONFIG?.LOCAL_SOCKS5_PORT ?? 0)
//        print(AppConfigs.V2RAY_CONFIG?.NOTIFICATION_DISCONNECT_BUTTON_NAME ?? "DISCONNECT")
//        print(AppConfigs.V2RAY_CONFIG?.REMARK ?? "Default Remark")
//        print(AppConfigs.V2RAY_CONFIG?.V2RAY_FULL_JSON_CONFIG ?? "Default Full JSON")

        // 如果配置为 nil, 不做任何操作
        if AppConfigs.V2RAY_CONFIG == nil {
            return
        }

        coreManager.startCore()

//        initializeV2Ray(result: result)
    }

    public func stopV2Ray(result: @escaping FlutterResult) {
        AppConfigs.V2RAY_STATE = .DISCONNECT
        coreManager.stopCore()

        initializeV2Ray(result: result)
    }
}
