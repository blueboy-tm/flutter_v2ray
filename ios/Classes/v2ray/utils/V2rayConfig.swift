class V2rayConfig: NSObject {
    // 单例实例
    static let shared = V2rayConfig()

    // 连接的 V2Ray 服务器地址
    var CONNECTED_V2RAY_SERVER_ADDRESS: String = ""
    // 连接的 V2Ray 服务器端口
    var CONNECTED_V2RAY_SERVER_PORT: String = ""
    // 本地 SOCKS5 代理端口
    var LOCAL_SOCKS5_PORT: Int = 10808
    // 本地 HTTP 代理端口
    var LOCAL_HTTP_PORT: Int = 10809
    // 被阻止的应用列表
    var BLOCKED_APPS: [String]? = nil
    // 绕过的子网列表
    var BYPASS_SUBNETS: [String]? = nil
    // 未格式化配置
    var V2RAT_JSON_CONFIG: String = ""
    // 完整的 V2Ray JSON 配置
    var V2RAY_FULL_JSON_CONFIG: String? = nil
    // 是否启用流量统计
    var ENABLE_TRAFFIC_STATISTICS: Bool = false
    // 备注
    var REMARK: String = ""
    // 应用名称
    var APPLICATION_NAME: String?
    // 应用图标的资源 ID
    var APPLICATION_ICON: Int = 0
    // 通知按钮名称
    var NOTIFICATION_DISCONNECT_BUTTON_NAME: String = "DISCONNECT"

    override private init() {
        super.init()
        // 初始化配置为默认值
    }

    // 设置 V2Ray 配置（如果需要，提供一个统一的接口）
    func configure(
        connectedServerAddress: String,
        connectedServerPort: String,
        localSocks5Port: Int = 10808,
        localHttpPort: Int = 10809,
        blockedApps: [String]? = nil,
        bypassSubnets: [String]? = nil,
        remark: String = "",
        applicationName: String? = nil,
        applicationIcon: Int = 0,
        notificationButtonName: String = "DISCONNECT"
    ) {
        self.CONNECTED_V2RAY_SERVER_ADDRESS = connectedServerAddress
        self.CONNECTED_V2RAY_SERVER_PORT = connectedServerPort
        self.LOCAL_SOCKS5_PORT = localSocks5Port
        self.LOCAL_HTTP_PORT = localHttpPort
        self.BLOCKED_APPS = blockedApps
        self.BYPASS_SUBNETS = bypassSubnets
        self.REMARK = remark
        self.APPLICATION_NAME = applicationName
        self.APPLICATION_ICON = applicationIcon
        self.NOTIFICATION_DISCONNECT_BUTTON_NAME = notificationButtonName
    }
}
