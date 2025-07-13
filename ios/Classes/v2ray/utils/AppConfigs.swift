import Foundation

/// AppConfigs 类用于管理应用程序的全局配置和状态。
class AppConfigs {
    /// V2Ray 连接模式，默认设置为 VPN TUN 模式。
    static var V2RAY_CONNECTION_MODE: V2RAY_CONNECTION_MODES = .VPN_TUN

    /// 应用程序名称，可选。
    static var APPLICATION_NAME: String = "SuLian VPN"

    /// 应用程序图标的资源 ID，默认为 0。
    static var APPLICATION_ICON: Int = 0

    /// 当前 V2Ray 配置对象，可选。
    static var V2RAY_CONFIG: V2rayConfig?

    /// 当前 V2Ray 状态，默认为断开连接状态。
    static var V2RAY_STATE: V2RAY_STATES = .DISCONNECT

    /// 是否启用流量和速度统计，默认为启用。
    static var ENABLE_TRAFFIC_AND_SPEED_STATISTICS: Bool = true

    /// 延迟测量 URL，可选。
    static var DELAY_URL: String?

    /// 连接状态
    static var NOTIFICATION_DISCONNECT_BUTTON_NAME: String = "DISCONNECT"
    
    /// IOS的 BundleIdentifier
    static var BUNDLE_IDENTIFIER = "com.sulian.app.v2.tunnel"

    /// V2Ray 服务命令的枚举，定义可以执行的操作。
    enum V2RAY_SERVICE_COMMANDS {
        case START_SERVICE // 启动服务
        case STOP_SERVICE // 停止服务
        case MEASURE_DELAY // 测量延迟
    }

    /// V2Ray 状态的枚举，表示当前的连接状态。
    enum V2RAY_STATES {
        case CONNECTED // 已连接状态
        case DISCONNECT // 断开连接状态
        case CONNECTING // 正在连接状态

        // 转换枚举为对应的大写字符串
        var description: String {
            switch self {
            case .CONNECTED:
                return "CONNECTED"
            case .DISCONNECT:
                return "DISCONNECTED"
            case .CONNECTING:
                return "CONNECTING"
            }
        }
    }

    /// V2Ray 连接模式的枚举，定义不同的连接方式。
    enum V2RAY_CONNECTION_MODES {
        case VPN_TUN // 使用 VPN TUN 模式
        case PROXY_ONLY // 仅使用代理模式
    }
}

