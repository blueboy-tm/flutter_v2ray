public struct V2RayStats {
    var time: String
    var uploadSpeed: String
    var downloadSpeed: String
    var totalUpload: String
    var totalDownload: String
    var state: String

    // 提供一个初始化默认值的方法
    static func defaultStats() -> V2RayStats {
        return V2RayStats(
            time: "00:00:00",
            uploadSpeed: "0",
            downloadSpeed: "0",
            totalUpload: "0",
            totalDownload: "0",
            state: AppConfigs.V2RAY_STATES.DISCONNECT.description
        )
    }
}
