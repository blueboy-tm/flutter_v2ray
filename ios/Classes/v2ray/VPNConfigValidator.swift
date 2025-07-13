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
 
    // 新增连接状态判断逻辑
    private func checkConnectionStatus(_ manager: NETunnelProviderManager?) -> Bool {
        guard let connection = manager?.connection else { return false }
        
        switch connection.status {
        case .connected, .connecting, .reasserting:  // 合并三种有效状态
            return true
        default:
            return false
        }
    }

    /// 初始化时同步检查
    public func checkInitialState(changeHandler: @escaping VpnStausChangeCallback) {
        let semaphore = DispatchSemaphore(value: 0)
        var isValid = false
        
        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            defer { semaphore.signal() }
            
            // 1. 检查配置是否存在
            let configExists = managers?.contains {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConfigs.BUNDLE_IDENTIFIER
            } ?? false
//            print("configExists \(configExists)")
            
            // 2. 检查活动配置
            let activeConfig = managers?.first { $0.isEnabled }
//            print("activeConfig \(activeConfig)")
            
            let isActiveValid = activeConfig.map {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppConfigs.BUNDLE_IDENTIFIER
            } ?? false
//            print("isActiveValid \(isActiveValid)")
            
            let activeManager = managers?.first { $0.isEnabled }
            let isConnected = self.checkConnectionStatus(activeManager)
            
            print("isConnected \(isConnected)")
            
            // 最终有效性 = 配置存在 + 已启用 + 已连接
            isValid = configExists && isActiveValid && isConnected
            
            changeHandler(isValid)
        }
    }
}
