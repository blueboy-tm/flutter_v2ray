import Flutter
import NetworkExtension

public class VPNConfigValidator {
    // 单例
    private static var sharedVPNConfigValidator: VPNConfigValidator = .init()
    public class func shared() -> VPNConfigValidator {
        return sharedVPNConfigValidator
    }
    
    public typealias VpnStausChangeCallback = (Bool) -> Void
    
//    private var currentCallback: VpnStausChangeCallback
 
        // New connection status check logic
    private func checkConnectionStatus(_ manager: NETunnelProviderManager?) -> Bool {
        guard let connection = manager?.connection else { return false }
        
        switch connection.status {
        case .connected, .connecting, .reasserting:  // Merge three valid states
            return true
        default:
            return false
        }
    }

    /// Initial synchronous check
    public func checkInitialState(changeHandler: @escaping VpnStausChangeCallback) {
        let semaphore = DispatchSemaphore(value: 0)
        var isValid = false
        
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            defer { semaphore.signal() }
            
            // 1. Check if configuration exists
            let configExists = managers?.contains {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConfigs.BUNDLE_IDENTIFIER
            } ?? false
//            print("configExists \(configExists)")
            
            // 2. Check active configuration
            let activeConfig = managers?.first { $0.isEnabled }
//            print("activeConfig \(activeConfig)")
            
            let isActiveValid = activeConfig.map {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConfigs.BUNDLE_IDENTIFIER
            } ?? false
//            print("isActiveValid \(isActiveValid)")
            
            let activeManager = managers?.first { $0.isEnabled }
            let isConnected = self.checkConnectionStatus(activeManager)
            
            print("isConnected \(isConnected)")
            
            // Final validity = configuration exists + enabled + connected
            isValid = configExists && isActiveValid && isConnected
            
            changeHandler(isValid)
        }
    }
}
