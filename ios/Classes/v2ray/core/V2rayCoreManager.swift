import Flutter
import Foundation
import Network
import NetworkExtension
import os.log

let appLog = OSLog(subsystem: "com.group.sulian.app", category: "vpn_management")

// MARK: - 单例 V2rayCoreManager 实现（与 Java 类似）

public class V2rayCoreManager {
    private lazy var pligun = FlutterV2rayPlugin.shared()

    private static var sharedV2rayCoreManager: V2rayCoreManager = .init()

    public class func shared() -> V2rayCoreManager {
        return sharedV2rayCoreManager
    }

    private var manager = NETunnelProviderManager.shared()
    private lazy var networkMonitor: NetworkMonitor = .shared()

    var isLibV2rayCoreInitialized = false
    var V2RAY_STATE: AppConfigs.V2RAY_STATES = .DISCONNECT

    private var trafficStatsTimer: Timer?
    private var startTime: Date?

    // MARK: - 设置监听器

    public func setUpListener() {
        stopTrafficStatsTimer()

        // 初始化配置项
        isLibV2rayCoreInitialized = true
        V2RAY_STATE = .DISCONNECT

        // Record the start time
        startTime = Date()
        #if DEBUG
            // 调用 startTrafficStatsTimer 启动定时器
            startTrafficStatsTimer()
        #endif
    }

    // MARK: - 启动VPN核心

    public func startCore() {
        guard isLibV2rayCoreInitialized else {
            print("Error: V2rayCoreManager must be initialized before starting.")
            return
        }

        V2RAY_STATE = .CONNECTED
        loadVPNConfigurationAndStartTunnel()

//        networkMonitor.startNetworkMonitoring { isChange in
//            if isChange {
//                self.manager.connection.stopVPNTunnel()
//                // 延迟 3 秒再尝试启动 VPN
//                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
//                    do {
//                        try self.manager.connection.startVPNTunnel()
//                        os_log("网络监听变化启动VPN成功", log: appLog, type: .info)
//                    } catch {
//                        os_log("网络监听变化启动VPN失败", log: appLog, type: .info)
//                    }
//                }
//            }
//        }
    }

    // MARK: - 创建VPN协议

    private func createVPNProtocol() -> NETunnelProviderProtocol {
        let v2rayConfig = V2rayConfig.shared // 创建 V2rayConfig 实例
        let port = v2rayConfig.LOCAL_SOCKS5_PORT
        let tunnelProtocol = NETunnelProviderProtocol()
        let vless = AppConfigs.V2RAY_CONFIG?.V2RAY_FULL_JSON_CONFIG ?? ""
        tunnelProtocol.serverAddress = AppConfigs.APPLICATION_NAME
        tunnelProtocol.providerConfiguration = ["vless": vless, "port": port]
        tunnelProtocol.providerBundleIdentifier = AppConfigs.BUNDLE_IDENTIFIER
        return tunnelProtocol
    }

    // MARK: - 加载现有VPN配置并启动VPN隧道

    private func loadVPNConfigurationAndStartTunnel() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self = self else { return }
            let targetDescription = AppConfigs.APPLICATION_NAME
            let existingManager = managers?.first { $0.localizedDescription == targetDescription }

            if let existingManager = existingManager {
                // 直接复用现有配置（不重复操作）
                self.manager = existingManager
                self.manager.isEnabled = true
                self.manager.saveToPreferences { _ in
                    self.manager.loadFromPreferences { _ in
                        self.manager.saveToPreferences { _ in
                            self.manager.loadFromPreferences { _ in
                                self.startVPNTunnel()
                            }
                        }
                    }
                }
            } else {
                // 首次创建配置时，执行两次 save+load（核心改动）
                let tunnelProtocol = createVPNProtocol()
                let newManager = NETunnelProviderManager()
                newManager.protocolConfiguration = tunnelProtocol
                newManager.localizedDescription = targetDescription
                newManager.isEnabled = true

                // 第一次保存和加载
                newManager.saveToPreferences { _ in
                    newManager.loadFromPreferences { _ in
                        // 第二次保存和加载
                        newManager.saveToPreferences { _ in
                            self.manager = newManager
                            newManager.loadFromPreferences { _ in
                                self.startVPNTunnel()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: -  启动VPN隧道

    private func startVPNTunnel() {
        do {
            try manager.connection.startVPNTunnel()
            os_log("VPN 核心已启用", log: appLog, type: .info)
        } catch let vpnError as NSError {
            os_log("Failed to start VPN tunnel: %{public}@", log: appLog, type: .error, vpnError.localizedDescription)
            os_log("Error code: %{public}d", log: appLog, type: .error, vpnError.code)

            // 添加更详细的错误处理
            switch vpnError.code {
            case NEVPNError.configurationInvalid.rawValue:
                os_log("配置无效", log: appLog, type: .error)
            case NEVPNError.configurationStale.rawValue:
                os_log("配置已过期", log: appLog, type: .error)
            case NEVPNError.connectionFailed.rawValue:
                os_log("连接失败", log: appLog, type: .error)
            default:
                os_log("未知VPN错误", log: appLog, type: .error)
            }
        }
    }

    // MARK: - 停止核心逻辑

    public func stopCore() {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            guard let managers = managers, error == nil else {
                return
            }

            // 查找特定的 VPN 配置
            if let targetManager = managers.first(where: { $0.localizedDescription == AppConfigs.APPLICATION_NAME }) {
                // 找到匹配的配置
                self.manager = targetManager
                self.manager.loadFromPreferences { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        os_log("加载配置失败: %@", log: appLog, type: .error, error.localizedDescription)
                        return
                    }

                    // 更新内部状态
                    V2RAY_STATE = .DISCONNECT

                    self.manager.saveToPreferences { error in
                        if let error = error {
                            os_log("保存配置失败: %@", log: appLog, type: .error, error.localizedDescription)
                            return
                        }

                        // 确认配置已保存后再停止隧道
                        self.manager.connection.stopVPNTunnel()
                        self.stopTrafficStatsTimer()
                        os_log("VPN 核心已停止", log: appLog, type: .info)
                    }
                }
            }
        }
    }

    // MARK: - 封装获取流量统计和发送到 Flutter 的功能

    func getTrafficStatsAndSendToFlutter() {
        guard let vpnConnection = manager.connection as? NETunnelProviderSession else {
            print("Error: VPN connection is not available.")
            return
        }

        let message: [String: Any] = ["command": "getTrafficStats"]
        do {
            let messageData = try JSONSerialization.data(withJSONObject: message, options: [])

            try vpnConnection.sendProviderMessage(messageData) { response in
                guard let response = response else {
                    print("No response received")
                    return
                }

                do {
                    if let responseJSON = try JSONSerialization.jsonObject(with: response, options: []) as? [String: Any] {
                        // 定义要提取的键
                        let keys = ["totalUpload", "downloadSpeed", "totalDownload", "uploadSpeed"]

                        var totalUpload = 0
                        var downloadSpeed = 0
                        var totalDownload = 0
                        var uploadSpeed = 0

                        // 遍历键，获取对应的值
                        for key in keys {
                            if let value = responseJSON[key] as? Int {
                                // 根据键存储对应的值
                                switch key {
                                case "totalUpload":
                                    totalUpload = value
                                case "downloadSpeed":
                                    downloadSpeed = value
                                case "totalDownload":
                                    totalDownload = value
                                case "uploadSpeed":
                                    uploadSpeed = value
                                default:
                                    break
                                }
                            }
                        }

                        let connectStatus = AppConfigs.V2RAY_STATE.description
                        // Calculate duration
                        let duration = self.getDurationString()
                        // 将值传递到 Flutter
                        self.pligun.sendEventToFlutter([
                            duration, // 持续时间
                            "\(uploadSpeed)", // 上传速度
                            "\(downloadSpeed)", // 下载速度
                            "\(totalUpload)", // 总上传
                            "\(totalDownload)", // 总下载
                            connectStatus // 当前状态
                        ])
                    } else {
                        print("Failed to decode response as JSON")
                    }
                } catch {
                    print("Error decoding JSON: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Error sending provider message: \(error.localizedDescription)")
        }
    }

    // MARK: - 定时每1秒调用一次

    func startTrafficStatsTimer() {
        trafficStatsTimer?.invalidate()
        trafficStatsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.getTrafficStatsAndSendToFlutter()
        }
    }

    private func stopTrafficStatsTimer() {
        trafficStatsTimer?.invalidate()
        trafficStatsTimer = nil
    }

    private func getDurationString() -> String {
        guard let startTime = startTime else {
            return "00:00:00"
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
