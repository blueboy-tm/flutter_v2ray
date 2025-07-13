import Foundation
import os.log
import Tun2SocksKit

public class TrafficMonitor {
    private var trafficMonitor: DispatchSourceTimer?
    private let trafficMonitorQueue = DispatchQueue(label: "com.yourcompany.networkextension.traffic.monitor")

    private var lastUploadBytes = 0
    private var lastDownloadBytes = 0

    private var uploadSpeed: Int = 0
    private var downloadSpeed: Int = 0
    private var totalUpload: Int = 0
    private var totalDownload: Int = 0

    private var log: OSLog {
        return OSLog(subsystem: "com.yourcompany.networkextension", category: "traffic_monitor")
    }

    // 定义闭包回调
    public var onTrafficUpdate: (([String: Any]) -> Void)?

   

    public func start() {
        trafficMonitor = DispatchSource.makeTimerSource(queue: trafficMonitorQueue)
        trafficMonitor?.schedule(deadline: .now(), repeating: .seconds(1))
        trafficMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }

            // 获取当前流量数据
            let currentUpload = Tun2SocksKit.Socks5Tunnel.stats.up
            let currentDownload = Tun2SocksKit.Socks5Tunnel.stats.down

            // 计算增量（每秒上传和下载流量）
            let uploadBytesDelta = currentUpload.bytes - lastUploadBytes
            let downloadBytesDelta = currentDownload.bytes - lastDownloadBytes

            // 更新上一次流量数据
            lastUploadBytes = currentUpload.bytes
            lastDownloadBytes = currentDownload.bytes

            // 更新速率（字节/秒）
            uploadSpeed = uploadBytesDelta
            downloadSpeed = downloadBytesDelta

            // 更新总流量，单位转换为KB
            totalUpload = currentUpload.bytes
            totalDownload = currentDownload.bytes

//            // 打印结果
//            os_log("Upload speed: %{public}@ KB/sec", log: log, type: .info, "\(uploadSpeed)")
//            os_log("Download speed: %{public}@ KB/sec", log: log, type: .info, "\(downloadSpeed)")
//            os_log("Total uploaded: %{public}@ KB", log: log, type: .info, "\(totalUpload)")
//            os_log("Total downloaded: %{public}@ KB", log: log, type: .info, "\(totalDownload)")

            // 如果设置了回调，传递更新的数据
            onTrafficUpdate?([
                "uploadSpeed": uploadSpeed,
                "downloadSpeed": downloadSpeed,
                "totalUpload": totalUpload,
                "totalDownload": totalDownload
            ])
        }
        trafficMonitor?.resume()
    }

    public func stop() {
        trafficMonitor?.cancel()
        trafficMonitor = nil
    }

    public func getStats() -> [String: Any] {
        return [
            "uploadSpeed": uploadSpeed,
            "downloadSpeed": downloadSpeed,
            "totalUpload": totalUpload,
            "totalDownload": totalDownload
        ]
    }
}
