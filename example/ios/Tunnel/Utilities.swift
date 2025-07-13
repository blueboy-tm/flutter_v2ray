import Foundation
import os.log

let utilLog = OSLog(subsystem: "com.yourcompany.networkextension", category: "network_utils")

/// Utilities 类提供各种实用工具方法。
public class Utilities {
    /// 获取配置文件保存路径
    /// - Parameter fileName: 文件名（带扩展名）
    /// - Returns: 完整的文件路径
    static func getConfigFilePath(fileName: String) -> String {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentDirectory.appendingPathComponent(fileName).path
    }

    /// 获取资源文件的路径
    /// - Parameters:
    ///   - resourceName: 资源文件名称（不包含扩展名）
    ///   - resourceType: 资源文件类型（扩展名）
    /// - Returns: 资源文件的路径，如果文件不存在则返回 `nil`
    static func getResourceFilePath(resourceName: String, resourceType: String) -> String? {
        return Bundle.main.path(forResource: resourceName, ofType: resourceType)
    }

    /// 获取日志文件路径
    /// - Parameter fileName: 日志文件名，默认为 "tun2socks_log.txt"
    /// - Returns: 完整的日志文件路径
    static func getLogFilePath(fileName: String = "tun2socks_log.txt") -> String {
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("无法获取文档目录路径")
        }
        return documentDirectory.appendingPathComponent(fileName).path
    }

    /// Base64 编码
    /// - Parameter string: 原始字符串
    /// - Returns: Base64 编码后的字符串
    static func base64Encode(_ string: String) -> String {
        return Data(string.utf8).base64EncodedString()
    }

    /// 解码 Base64 字符串并解析为 JSON 对象。
    /// - Parameter base64String: Base64 编码的字符串
    /// - Returns: 字典形式的 JSON 对象，如果解码或解析失败，则返回 `nil`
    static func decodeBase64AndParseJSON(_ base64String: String) -> [String: Any]? {
        guard
            let decodedData = Data(base64Encoded: base64String),
            let jsonString = String(data: decodedData, encoding: .utf8),
            let jsonData = jsonString.data(using: .utf8)
        else {
            os_log("Base64 解码或 JSON 数据转换失败", log: utilLog, type: .error)
            return nil
        }

        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                return jsonObject
            }
        } catch {
            os_log("JSON 解析失败: %{public}@", log: utilLog, type: .error, error.localizedDescription)
        }
        return nil
    }

    /// 将配置字符串写入指定路径的文件。
    /// - Parameters:
    ///   - config: 配置字符串
    ///   - path: 文件路径
    /// - Returns: 写入是否成功
    static func writeConfigToFile(config: String, path: String) -> Bool {
        let fileManager = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent

        // 确保目录存在
        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
            } catch {
                os_log("无法创建目录: %{public}@", log: utilLog, type: .error, error.localizedDescription)
                return false
            }
        }

        // 写入配置文件
        do {
            try config.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            os_log("配置文件写入成功: %{public}@", log: utilLog, type: .info, path)
            return true
        } catch {
            os_log("写入配置文件失败: %{public}@", log: utilLog, type: .error, error.localizedDescription)
            return false
        }
    }
}
