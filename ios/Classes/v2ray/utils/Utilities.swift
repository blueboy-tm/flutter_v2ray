import Foundation
import UIKit

/// Utilities 类提供各种实用工具方法。
class Utilities {
    /// 将整数转换为两位数字的字符串格式。
    /// - Parameter value: 要转换的整数值
    /// - Returns: 格式化后的字符串
    static func convertIntToTwoDigit(_ value: Int) -> String {
        return String(format: "%02d", value) // 使用格式化字符串返回两位数
    }

    /// Base64 编码
    static func base64Encode(_ string: String) -> String {
        return Data(string.utf8).base64EncodedString()
    }

    /// Decode a Base64 string and parse it as a JSON object.
    /// - Parameter base64String: The Base64-encoded string to decode.
    /// - Returns: A dictionary representing the parsed JSON object, or `nil` if the decoding or parsing fails.
    static func decodeBase64AndParseJSON(_ base64String: String) -> [String: Any]? {
        // Step 1: Decode Base64 string
        guard let decodedData = Data(base64Encoded: base64String),
              let jsonString = String(data: decodedData, encoding: .utf8)
        else {
            print("Failed to decode Base64 string.")
            return nil
        }

        // Step 2: Parse JSON string into a dictionary
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("Failed to convert JSON string to data.")
            return nil
        }

        do {
            // Convert JSON data to a dictionary
            if let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                return jsonObject
            }
        } catch {
            print("Failed to parse JSON: \(error)")
        }

        return nil
    }

    /// 解析 V2Ray JSON 配置文件并生成 V2rayConfig 对象。
    /// - Parameters:
    ///   - remark: 备注
    ///   - config: JSON 配置字符串
    ///   - blockedApplication: 被阻止的应用列表
    ///   - bypassSubnets: 绕过的子网列表
    /// - Returns: V2rayConfig 对象，或在失败时返回 nil
    static func parseV2rayJsonFile(remark: String, config: String, blockedApplication: [String], bypassSubnets: [String]) -> V2rayConfig? {
        let v2rayConfig = V2rayConfig.shared // 创建 V2rayConfig 实例
        v2rayConfig.V2RAT_JSON_CONFIG = config // 未格式化配置
        v2rayConfig.REMARK = remark // 设置备注
        v2rayConfig.BLOCKED_APPS = blockedApplication // 设置被阻止的应用
        v2rayConfig.BYPASS_SUBNETS = bypassSubnets // 设置绕过的子网
        v2rayConfig.APPLICATION_ICON = AppConfigs.APPLICATION_ICON // 设置应用图标
        v2rayConfig.APPLICATION_NAME = AppConfigs.APPLICATION_NAME // 设置应用名称
        v2rayConfig.NOTIFICATION_DISCONNECT_BUTTON_NAME = AppConfigs.NOTIFICATION_DISCONNECT_BUTTON_NAME

        do {
            // 将 JSON 字符串转换为字典
            if let configData = config.data(using: .utf8),
               let configJson = try JSONSerialization.jsonObject(with: configData, options: []) as? [String: Any]
            {
                // 解析入站配置
                if let inbounds = configJson["inbounds"] as? [[String: Any]] {
                    for inbound in inbounds {
                        if let protocolType = inbound["protocol"] as? String {
                            // 根据协议类型设置相应的端口
                            if protocolType == "socks", let port = inbound["port"] as? Int {
                                v2rayConfig.LOCAL_SOCKS5_PORT = port
                            } else if protocolType == "http", let port = inbound["port"] as? Int {
                                v2rayConfig.LOCAL_HTTP_PORT = port
                            }
                        }
                    }
                }

                // 解析出站配置
                if let outbounds = configJson["outbounds"] as? [[String: Any]],
                   let settings = outbounds.first?["settings"] as? [String: Any],
                   let vnext = settings["vnext"] as? [[String: Any]],
                   let firstVnext = vnext.first
                { // 获取第一个 vnext 项
                    v2rayConfig.CONNECTED_V2RAY_SERVER_ADDRESS = firstVnext["address"] as? String ?? "" // 服务器地址
                    v2rayConfig.CONNECTED_V2RAY_SERVER_PORT = String(firstVnext["port"] as? Int ?? 0) // 服务器端口，确保转换为字符串
                }

                // 移除不必要的字段
                var mutableConfigJson = configJson
                mutableConfigJson.removeValue(forKey: "policy")
                mutableConfigJson.removeValue(forKey: "stats")

                // 如果启用流量和速度统计，添加相应配置
                if AppConfigs.ENABLE_TRAFFIC_AND_SPEED_STATISTICS {
                    let policy: [String: Any] = [
                        "levels": ["8": ["connIdle": 300, "downlinkOnly": 1, "handshake": 4, "uplinkOnly": 1]],
                        "system": ["statsOutboundUplink": true, "statsOutboundDownlink": true]
                    ]
                    mutableConfigJson["policy"] = policy
                    mutableConfigJson["stats"] = [:]
                    v2rayConfig.ENABLE_TRAFFIC_STATISTICS = true // 启用流量统计
                }

                // 将字典转换回 JSON 数据
                let jsonData = try JSONSerialization.data(withJSONObject: mutableConfigJson, options: [])
                v2rayConfig.V2RAY_FULL_JSON_CONFIG = String(data: jsonData, encoding: .utf8) // 设置完整的 JSON 配置
            }
        } catch {
            print("parseV2rayJsonFile failed: \(error)") // 处理解析失败的错误
            return nil // 返回 nil
        }

        return v2rayConfig // 返回解析后的配置
    }
}
