import Foundation
import Network
import os.log


let networkLog = OSLog(subsystem: "com.group.sulian.app", category: "vpn_networkMonitor")

public class NetworkMonitor {
    
    // MARK: - Singleton
    private static var sharedNetworkMonitor: NetworkMonitor = .init()
    public class func shared() -> NetworkMonitor {
        return sharedNetworkMonitor
    }
    
    // MARK: - Properties
    private var networkMonitor: NWPathMonitor?
    private var lastNetworkType: String?
    private var currentCallback: NetworkChangeCallback?
    private var lastUpdateTime: Date?
    private let minUpdateInterval: TimeInterval = 1.0 // Minimum 1 second between updates
    
    // MARK: - Type Alias
    public typealias NetworkChangeCallback = (Bool) -> Void
    
    // MARK: - Public Methods
    
    /// Start monitoring network changes
    public func startNetworkMonitoring(changeHandler: @escaping NetworkChangeCallback) {
        stopNetworkMonitoring() // Ensure previous monitoring is stopped
        
        networkMonitor = NWPathMonitor()
        currentCallback = changeHandler
        
        let queue = DispatchQueue(label: "com.group.sulian.networkMonitorQueue")
        
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            // Check if enough time has passed since last update
            if let lastTime = self.lastUpdateTime,
               Date().timeIntervalSince(lastTime) < self.minUpdateInterval {
                return
            }
            
            let currentType = self.getNetworkTypeDescription(path)
            let isRelevantType = (currentType == "WiFi" || currentType == "Cellular")
            
            // Only proceed if network is satisfied and type is relevant
            guard path.status == .satisfied, isRelevantType else {
                if path.status != .satisfied {
                    os_log("Network path is not satisfied", log: appLog, type: .debug)
                }
                return
            }
            
            // Log only when there's an actual change or first detection
            if self.lastNetworkType != currentType || self.lastNetworkType == nil {
                os_log("NetworkUpdate - Current: %{public}@, Last: %{public}@",
                       log: networkLog,
                       currentType,
                       self.lastNetworkType ?? "nil")
            }
            
            // Handle first detection
            if self.lastNetworkType == nil {
                self.lastNetworkType = currentType
                os_log("Initial network type: %{public}@", log: appLog, currentType)
                return
            }
            
            // Check for actual network type switch
            if self.lastNetworkType != currentType {
                let isSwitch = (self.lastNetworkType == "WiFi" && currentType == "Cellular") ||
                               (self.lastNetworkType == "Cellular" && currentType == "WiFi")
                
                os_log("Network switch detected: %{public}@ -> %{public}@ (isSwitch: %{public}@)",
                       log: appLog,
                       self.lastNetworkType ?? "nil",
                       currentType,
                       isSwitch ? "YES" : "NO")
                
                self.lastUpdateTime = Date()
                self.lastNetworkType = currentType
                
                DispatchQueue.main.async {
                    self.currentCallback?(isSwitch)
                }
            }
        }
        
        networkMonitor?.start(queue: queue)
    }
    
    /// Stop monitoring network changes
    public func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        currentCallback = nil
        lastNetworkType = nil
        lastUpdateTime = nil
    }
    
    // MARK: - Private Methods
    
    /// Get description of current network type
    private func getNetworkTypeDescription(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "WiFi"
        } else if path.usesInterfaceType(.cellular) {
            return "Cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "Ethernet"
        } else {
            return "Other"
        }
    }
}
