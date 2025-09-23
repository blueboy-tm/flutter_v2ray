import Foundation
import NetworkExtension
import os.log

/// V2Ray Core Manager handles VPN operations
public class V2rayCoreManager {
    private static var instance: V2rayCoreManager?
    private let log = OSLog(subsystem: "com.everythingStudio.parsVpn", category: "v2ray_core")
    
    private var vpnManager: NETunnelProviderManager?
    private var vpnStatus: NEVPNStatus = .invalid
    
    // Singleton pattern
    public static func shared() -> V2rayCoreManager {
        if instance == nil {
            instance = V2rayCoreManager()
        }
        return instance!
    }
    
    private init() {
        setupVPNStatusObserver()
    }
    
    /// Setup VPN status observer
    private func setupVPNStatusObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnStatusDidChange),
            name: .NEVPNStatusDidChange,
            object: nil
        )
    }
    
    /// VPN status change handler
    @objc private func vpnStatusDidChange(notification: Notification) {
        guard let connection = notification.object as? NEVPNConnection else { return }
        
        vpnStatus = connection.status
        os_log("VPN status changed to: %{public}@", log: log, type: .info, connection.status.description)
        
        // Notify Flutter about status change
        let statusMessage = connection.status.description
        FlutterV2rayPlugin.shared().sendEventToFlutter([
            "0", // time
            "0", // uploadSpeed  
            "0", // downloadSpeed
            "0", // totalUpload
            "0", // totalDownload
            statusMessage // status
        ])
    }
    
    /// Start VPN connection
    public func startVPN(config: String, completion: @escaping (Bool, Error?) -> Void) {
        loadVPNConfigurationAndStartTunnel(config: config, completion: completion)
    }
    
    /// Stop VPN connection
    public func stopVPN(completion: @escaping (Bool, Error?) -> Void) {
        guard let manager = vpnManager else {
            completion(false, NSError(domain: "V2rayCore", code: 1, userInfo: [NSLocalizedDescriptionKey: "VPN manager not initialized"]))
            return
        }
        
        manager.connection.stopVPNTunnel()
        completion(true, nil)
    }
    
    /// Get current VPN status
    public func getVPNStatus() -> NEVPNStatus {
        return vpnStatus
    }
    
    /// Set up listener (for compatibility with V2rayController)
    public func setUpListener() {
        os_log("Setting up listener", log: log, type: .info)
        // Listener is already set up in init, no additional action needed
    }
    
    /// Start core (for compatibility with V2rayController)
    public func startCore() {
        guard let config = AppConfigs.V2RAY_CONFIG else {
            os_log("No V2Ray config available", log: log, type: .error)
            return
        }
        
        let configString = config.V2RAY_FULL_JSON_CONFIG ?? config.REMARK
        startVPN(config: configString) { success, error in
            if let error = error {
                os_log("Failed to start VPN: %{public}@", log: self.log, type: .error, error.localizedDescription)
            } else {
                os_log("VPN started successfully", log: self.log, type: .info)
            }
        }
    }
    
    /// Stop core (for compatibility with V2rayController)
    public func stopCore() {
        stopVPN { success, error in
            if let error = error {
                os_log("Failed to stop VPN: %{public}@", log: self.log, type: .error, error.localizedDescription)
            } else {
                os_log("VPN stopped successfully", log: self.log, type: .info)
            }
        }
    }
    
    /// Load VPN configuration and start tunnel
    private func loadVPNConfigurationAndStartTunnel(config: String, completion: @escaping (Bool, Error?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                os_log("Failed to load VPN configurations: %{public}@", log: self?.log ?? OSLog.default, type: .error, error.localizedDescription)
                completion(false, error)
                return
            }
            
            // Find existing configuration or create new one
            let manager = managers?.first ?? NETunnelProviderManager()
            self?.vpnManager = manager
            
            // Configure tunnel provider protocol
            let providerProtocol = NETunnelProviderProtocol()
            providerProtocol.providerBundleIdentifier = "com.everythingStudio.parsVpn.tunnel"
            providerProtocol.serverAddress = "127.0.0.1"
            providerProtocol.providerConfiguration = ["vless": config]
            
            manager.protocolConfiguration = providerProtocol
            manager.localizedDescription = "Persian VPN"
            manager.isEnabled = true
            
            // Save configuration
            manager.saveToPreferences { [weak self] saveError in
                if let error = saveError {
                    os_log("Failed to save VPN configuration: %{public}@", log: self?.log ?? OSLog.default, type: .error, error.localizedDescription)
                    completion(false, error)
                    return
                }
                
                // Start VPN tunnel
                do {
                    try manager.connection.startVPNTunnel()
                    os_log("VPN tunnel start initiated", log: self?.log ?? OSLog.default, type: .info)
                    completion(true, nil)
                } catch {
                    os_log("Failed to start VPN tunnel: %{public}@", log: self?.log ?? OSLog.default, type: .error, error.localizedDescription)
                    completion(false, error)
                }
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// Extension for NEVPNStatus description
extension NEVPNStatus {
    var description: String {
        switch self {
        case .invalid:
            return "DISCONNECTED"
        case .disconnected:
            return "DISCONNECTED"
        case .connecting:
            return "CONNECTING"
        case .connected:
            return "CONNECTED"
        case .reasserting:
            return "CONNECTING"
        case .disconnecting:
            return "DISCONNECTING"
        @unknown default:
            return "UNKNOWN"
        }
    }
}
