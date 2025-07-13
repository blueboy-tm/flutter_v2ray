import LibXray
import NetworkExtension
import os.log
import Tun2SocksKit

let log = OSLog(subsystem: "com.yourcompany.networkextension", category: "network_vpn")

class PacketTunnelProvider: NEPacketTunnelProvider {
    private let preferences = UserDefaults.standard

    // 创建 TrafficMonitor 实例
    let trafficMonitor = TrafficMonitor()

    /// 启动网络隧道
    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let config = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfig = config.providerConfiguration,
              let vmess = providerConfig["vmess"]
        else {
            os_log("配置错误，未找到 vmess 配置", log: log, type: .error)
            completionHandler(NSError(domain: "com.yourcompany.networkextension", code: 1, userInfo: [NSLocalizedDescriptionKey: "配置错误，未找到 vmess 配置"]))
            return
        }

        // 配置文件保存路径
        let configPath = Utilities.getConfigFilePath(fileName: "xray_config_runXray.json")

        // 写入 Xray 配置文件
        if !Utilities.writeConfigToFile(config: String(describing: vmess), path: configPath) {
            os_log("写入 Xray 配置文件失败", log: log, type: .error)
            completionHandler(NSError(domain: "com.yourcompany.networkextension", code: 2, userInfo: [NSLocalizedDescriptionKey: "写入 Xray 配置文件失败"]))
            return
        }
        let geoipPath = Utilities.getResourceFilePath(resourceName: "geoip", resourceType: "dat")

        let runRequest: [String: Any] = [
            "datDir": geoipPath ?? "", // 如果 geoipPath 为 nil，则使用空字符串
            "configPath": configPath // 同样处理 configPath 的 nil 情况
//            "maxMemory": 1024 // 设置最大内存
        ]

        // 将请求编码为 base64
        guard let utf8String = try? JSONSerialization.data(withJSONObject: runRequest, options: .prettyPrinted) else {
            os_log("请求数据编码失败", log: log, type: .error)
            completionHandler(NSError(domain: "com.yourcompany.networkextension", code: 3, userInfo: [NSLocalizedDescriptionKey: "请求数据编码失败"]))
            return
        }

        let base64Request = Utilities.base64Encode(String(data: utf8String, encoding: .utf8)!)

        // 调用 RunXray 函数
        let response = LibXrayRunXray(base64Request)

        // 解码响应
        guard let result = Utilities.decodeBase64AndParseJSON(response) else {
            os_log("解码响应失败", log: log, type: .error)
            completionHandler(NSError(domain: "com.yourcompany.networkextension", code: 4, userInfo: [NSLocalizedDescriptionKey: "解码响应失败"]))
            return
        }

        // 检查响应是否表示成功
        if let success = result["success"] as? Bool, success {
            os_log("RunXray 测试通过", log: log, type: .info)
        } else {
            os_log("RunXray 测试失败: %{public}@", log: log, type: .error, result["error"] as! CVarArg)
        }

        let networkSettings = configureNetworkSettings()
        setTunnelNetworkSettings(networkSettings) { error in
            if let error = error {
                os_log("设置隧道网络设置失败: %{public}@", log: log, type: .error, error.localizedDescription)
                completionHandler(error)
            } else {
                // 启动隧道后开始流量转发
                os_log("隧道网络设置成功", log: log, type: .info)

                // 调试日志：确认网络配置内容
                os_log("确认设置的网络配置: %{public}@", log: log, type: .debug, "\(networkSettings)")
                self.startTun2Socks()

                // 启动流量监控
//                self.startTrafficMonitoring()

                self.trafficMonitor.start()
                completionHandler(nil)
            }
        }
    }

    /// 停止网络隧道
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        LibXrayStopXray()
        Tun2SocksKit.Socks5Tunnel.quit()
        os_log("Stopping tunnel with reason: %{public}@", log: log, type: .info, reason.rawValue.description)
        completionHandler()
    }

    /// 处理主App发送过来的消息
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
//        os_log("Received app message: %{public}@", log: log, type: .info, messageData.debugDescription)

        guard let json = try? JSONSerialization.jsonObject(with: messageData, options: []) as? [String: Any],
              let command = json["command"] as? String
        else {
            os_log("Invalid message format", log: log, type: .error)
            completionHandler?(nil)
            return
        }

        switch command {
        case "getTrafficStats":
            handleGetTrafficStats(completionHandler: completionHandler)
        default:
            os_log("Unknown command received: %{public}@", log: log, type: .error, command)
            completionHandler?(nil)
        }
    }

    private func handleGetTrafficStats(completionHandler: ((Data?) -> Void)?) {
        let stats = trafficMonitor.getStats()
        // 安全地提取字典中的值并转换为 Int 类型
        if let uploadSpeed = stats["uploadSpeed"] as? Int,
           let downloadSpeed = stats["downloadSpeed"] as? Int,
           let totalUpload = stats["totalUpload"] as? Int,
           let totalDownload = stats["totalDownload"] as? Int
        {
            let trafficStats: [String: Any] = [
                "uploadSpeed": uploadSpeed,
                "downloadSpeed": downloadSpeed,
                "totalUpload": totalUpload,
                "totalDownload": totalDownload
            ]

            // 打印或使用 trafficStats
            print(trafficStats)
            do {
                let responseData = try JSONSerialization.data(withJSONObject: trafficStats, options: [])
                completionHandler?(responseData)
            } catch {
                os_log("Failed to encode traffic stats", log: log, type: .error)
                completionHandler?(nil)
            }
        }
    }

    /// 当设备即将进入睡眠状态时
    override func sleep(completionHandler: @escaping () -> Void) {
        os_log("Device entering sleep mode", log: log, type: .info)
        completionHandler()
    }

    /// 当设备从睡眠模式唤醒时
    override func wake() {
        os_log("Device waking up from sleep", log: log, type: .info)
    }

    func configureNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1500

        settings.ipv4Settings = {
            let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.1"], subnetMasks: ["255.255.255.0"])
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
            ipv4Settings.excludedRoutes = [] // 确保所有流量都经过隧道
            return ipv4Settings
        }()

        settings.dnsSettings = {
            let dnsSettings = NEDNSSettings(servers: ["8.8.8.8"])
            dnsSettings.matchDomains = [""]
            return dnsSettings
        }()

        return settings
    }

    func startTun2Socks() {
        let logFilePath = Utilities.getLogFilePath()

        let socks5Config = """
        tunnel:
            mtu: 1500

        socks5:
            port: 1081
            address: 127.0.0.1
            udp: 'udp'

        misc:
            task-stack-size: 20480
            connect-timeout: 5000
            read-write-timeout: 60000
            log-file: \(logFilePath)
            log-level: info
            limit-nofile: 65535

        """
        Tun2SocksKit.Socks5Tunnel.run(withConfig: .string(content: socks5Config)) { code in
            if code == 0 {
                os_log("Tun2Socks 启动成功", log: OSLog.default, type: .info)
            } else {
                os_log("Tun2Socks 启动失败, code: %{public}@", log: OSLog.default, type: .error, "\(code)")
            }
        }
    }
}
