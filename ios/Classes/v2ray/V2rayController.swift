import Flutter
import NetworkExtension
import os.log

let conLog = OSLog(subsystem: "com.group.sulian.app", category: "vpn_controller")

public class V2rayController {
    private lazy var pligun = FlutterV2rayPlugin.shared()

    // Single instance
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
        // Remove listener
        if let observer = vpnStatusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // Debounce timer variables
    var debounceTimer: Timer?
    let debounceInterval: TimeInterval = 0.5 // Set debounce interval to 0.5 seconds
    var timeoutTimer: Timer? // Add timeout timer

    // Set VPN status listener
    private func setupVPNStatusObserver(result: @escaping FlutterResult) {
        // Cancel all existing timers first
        debounceTimer?.invalidate()
        timeoutTimer?.invalidate()

        vpnStatusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            // Cancel previous debounce timer
            debounceTimer?.invalidate()

            // Set new debounce timer
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                os_log("VPN status change notification triggered", log: conLog, type: .debug)
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

    // Clean up observers and timers
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
        // Get string representation of V2RAY_STATE
        let connectStatus = AppConfigs.V2RAY_STATE.description
        let stats = V2RayStats.defaultStats()

        pligun.sendEventToFlutter([
            stats.time,
            stats.uploadSpeed,
            stats.downloadSpeed,
            stats.totalUpload,
            stats.totalDownload,
            connectStatus // Current status
        ])

        result(nil)
    }

    // Start V2ray
    public func startV2Ray(remark: String, config: String, blockedApps: [String], bypassSubnets: [String], proxyOnly: Bool, result: @escaping FlutterResult) {
        // Set up listener on first startup
        if vpnStatusObserver == nil {
            setupVPNStatusObserver(result: result)
        }

        coreManager.setUpListener()

        // Parse V2ray configuration
        guard let v2rayConfig = Utilities.parseV2rayJsonFile(remark: remark, config: config, blockedApplication: blockedApps, bypassSubnets: bypassSubnets) else {
            // If parsing fails, return directly
            return
        }

        AppConfigs.V2RAY_CONFIG = v2rayConfig

        // If configuration is nil, do nothing
        if AppConfigs.V2RAY_CONFIG == nil {
            return
        }

        coreManager.startCore()
    }

    public func stopV2Ray(result: @escaping FlutterResult) {
        AppConfigs.V2RAY_STATE = .DISCONNECT
        coreManager.stopCore()

        initializeV2Ray(result: result)
    }
}
