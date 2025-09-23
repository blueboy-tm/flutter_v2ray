import Flutter
import NetworkExtension
import UIKit
import UserNotifications

public class FlutterV2rayPlugin: NSObject, FlutterPlugin {
    // Static shared event stream instance
    public static var sharedEventSink: FlutterEventSink?

    // V2Ray controller singleton instance
    private lazy var controller: V2rayController = .shared()
    // V2Ray core manager singleton instance
    private lazy var coreManager: V2rayCoreManager = .shared()
    private lazy var vpnConfig: VPNConfigValidator = .shared()

    private static var sharedFlutterV2rayPlugin: FlutterV2rayPlugin = .init()

    public class func shared() -> FlutterV2rayPlugin {
        return sharedFlutterV2rayPlugin
    }

    // Register plugin to Flutter engine
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Define method channel and event channel for Flutter communication
        let methodChannel = FlutterMethodChannel(name: "flutter_v2ray", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_v2ray/status", binaryMessenger: registrar.messenger())

        // Use shared instance for consistency
        let instance = FlutterV2rayPlugin.shared()
        // Set plugin instance as method channel handler
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        // Set plugin instance as event channel stream handler
        eventChannel.setStreamHandler(instance)
    }

    // Method call handler mapping table for mapping method names to specific handler functions
    private lazy var methodHandlers: [String: (FlutterMethodCall, @escaping FlutterResult) -> Void] = [
        "startV2Ray": handleStartV2Ray, // Start V2Ray
        "stopV2Ray": handleStopV2Ray, // Stop V2Ray
        "initializeV2Ray": handleInitializeV2Ray, // Initialize V2Ray
        "getServerDelay": handleGetServerDelay, // Get server delay
        "getConnectedServerDelay": handleGetConnectedServerDelay, // Get connected server delay
        "requestPermission": handleRequestPermission, // Request VPN permission
        "getCoreVersion": handleGetCoreVersion, // Get core version
        "checkVPNState": handleCheckVPNState, // Check VPN state
    ]

    // Main method call handler function, matches method name and calls corresponding handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if let handler = methodHandlers[call.method] {
            handler(call, result)
        } else {
            result(FlutterMethodNotImplemented) // Method not implemented
        }
    }

    // Handle start V2Ray method
    private func handleStartV2Ray(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Parse required data from method call arguments
        guard let args = call.arguments as? [String: Any],
              let remark = args["remark"] as? String,
              let config = args["config"] as? String
        else {
            // Return error when arguments are missing or invalid
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid arguments for starting V2Ray", details: nil))
            return
        }
        // Get optional parameters
        let blockedApps = args["blocked_apps"] as? [String] ?? []
        let bypassSubnets = args["bypass_subnets"] as? [String] ?? []
        let proxyOnly = args["proxyOnly"] as? Bool ?? false

        // Call controller method to start V2Ray
        controller.startV2Ray(remark: remark, config: config, blockedApps: blockedApps, bypassSubnets: bypassSubnets, proxyOnly: proxyOnly, result: result)
    }

    // Handle stop V2Ray method
    private func handleStopV2Ray(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        controller.stopV2Ray(result: result)
    }

    // Handle initialize V2Ray method
    private func handleInitializeV2Ray(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Extract notification parameters (similar to Android)
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid arguments for initializing V2Ray", details: nil))
            return
        }
        
        let iconResourceName = args["notificationIconResourceName"] as? String ?? ""
        let iconResourceType = args["notificationIconResourceType"] as? String ?? ""
        
        print("Initializing V2Ray with notification icon: \(iconResourceName), type: \(iconResourceType)")
        
        // Check notification permission status for logging
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let statusMessage: String
            switch settings.authorizationStatus {
            case .authorized:
                statusMessage = "✅ Notifications authorized - VPN status will be shown"
            case .denied:
                statusMessage = "⚠️ Notifications denied - VPN will work silently"
            case .notDetermined:
                statusMessage = "❓ Notifications not requested yet - will ask during permission request"
            case .provisional:
                statusMessage = "⚠️ Notifications provisional - limited functionality"
            case .ephemeral:
                statusMessage = "⚠️ Notifications ephemeral - temporary permission"
            @unknown default:
                statusMessage = "❓ Unknown notification status"
            }
            print("Notification Status: \(statusMessage)")
        }
        
        controller.initializeV2Ray(result: result)
    }

    // Send message to Flutter
    public func sendEventToFlutter(_ message: Any) {
        if let eventSink = FlutterV2rayPlugin.sharedEventSink {
            DispatchQueue.main.async {
                eventSink(message) // Ensure events are sent on main thread
            }
        }
    }
    
    // Helper method to check if notifications should be shown (for debugging)
    private func canShowNotifications(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let canShow = settings.authorizationStatus == .authorized || 
                         settings.authorizationStatus == .provisional
            completion(canShow)
        }
    }

    // Get server delay
    private func handleGetServerDelay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let config = args["config"] as? String,
              let url = args["url"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid arguments for getting server delay", details: nil))
            return
        }
        getServerDelay(config: config, url: url, result: result)
    }

    // Get connected server delay
    private func handleGetConnectedServerDelay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let url = args["url"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid arguments for getting connected server delay", details: nil))
            return
        }
        getConnectedServerDelay(url: url, result: result)
    }

    // Request VPN permission
    private func handleRequestPermission(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Request notification permission first (non-blocking for VPN functionality)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { notificationGranted, notificationError in
            // Log notification permission result but don't block VPN functionality
            if let error = notificationError {
                print("⚠️ Notification permission error (VPN will still work): \(error.localizedDescription)")
            } else if notificationGranted {
                print("✅ Notification permission granted - VPN status notifications will be available")
            } else {
                print("⚠️ Notification permission denied - VPN will work but no status notifications")
            }
        }
        
        // Check VPN permission status independently
        self.checkVPNPermissionStatus(result: result)
    }
    
    // Separate method to check VPN permission status
    private func checkVPNPermissionStatus(result: @escaping FlutterResult) {
        NEVPNManager.shared().loadFromPreferences { [weak self] loadError in
            DispatchQueue.main.async {
                if let error = loadError {
                    // If we can't load preferences, it might be the first time
                    // The system will show VPN permission dialog when actually starting VPN
                    print("VPN preferences not loaded (first time): \(error.localizedDescription)")
                    print("VPN permission will be requested by system when starting connection")
                    result(true) // Allow VPN attempt - system will handle permission
                } else {
                    // VPN preferences loaded successfully
                    print("✅ VPN permission check successful - ready to connect")
                    result(true)
                }
            }
        }
    }

    // Get core version
    private func handleGetCoreVersion(_ call: FlutterMethodCall, result: FlutterResult) {
        do {
            let baseVersion = String(cString: CGoXrayVersion())
            // Call the function
            if let jsonObject = Utilities.decodeBase64AndParseJSON(baseVersion) {
                // Access individual keys in the JSON object
                if let data = jsonObject["data"] as? String {
                    result("v\(data)")
                } else {
                    result(FlutterError(code: "VERSION_PARSE_ERROR", message: "Unable to parse version data", details: nil))
                }
            } else {
                result(FlutterError(code: "VERSION_DECODE_ERROR", message: "Unable to decode version information", details: nil))
            }
        } catch {
            result(FlutterError(code: "VERSION_ERROR", message: "Failed to get version number", details: error.localizedDescription))
        }
    }

    // Check VPN state
    private func handleCheckVPNState(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        vpnConfig.checkInitialState { isValid in
            if isValid == true {
//                print("isValid \(isValid)")
                // Get V2RAY_STATE string representation
                
                let connectStatus = AppConfigs.V2RAY_STATES.CONNECTED.description
                let stats = V2RayStats.defaultStats()

                self.sendEventToFlutter([
                    stats.time,
                    stats.uploadSpeed,
                    stats.downloadSpeed,
                    stats.totalUpload,
                    stats.totalDownload,
                    connectStatus, // Current state
                ])
            } else {
                self.controller.stopV2Ray(result: result)
            }
        }
    }

    // Get server delay
    private func getServerDelay(config: String, url: String, result: @escaping FlutterResult) {
        // Perform actual ping test to measure server delay
        guard let pingURL = URL(string: url) else {
            sendFlutterError(to: result, code: "INVALID_URL", message: "Invalid ping URL: \(url)")
            return
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: pingURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            let delay: Int
            
            if let error = error {
                print("Ping error for \(url): \(error.localizedDescription)")
                delay = -1 // Indicate timeout/error
            } else if let httpResponse = response as? HTTPURLResponse {
                let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
                delay = Int(timeElapsed * 1000) // Convert to milliseconds
                print("Ping success for \(url): \(delay)ms, status: \(httpResponse.statusCode)")
            } else {
                delay = -1 // No valid response
            }
            
            DispatchQueue.main.async {
                result(delay)
            }
        }
        
        task.resume()
    }

    // Get connected server delay
    private func getConnectedServerDelay(url: String, result: @escaping FlutterResult) {
        // Use the same ping logic for connected server delay
        getServerDelay(config: "", url: url, result: result)
    }

    // Handle Flutter error (unified error handling)
    private func sendFlutterError(to result: @escaping FlutterResult, code: String, message: String, details: String? = nil) {
        result(FlutterError(
            code: code,
            message: message,
            details: details
        ))
    }
}

extension FlutterV2rayPlugin: FlutterStreamHandler {
    // Listen to Flutter event channel
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        FlutterV2rayPlugin.sharedEventSink = events
        return nil
    }

    // Stop listening to Flutter event channel
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        FlutterV2rayPlugin.sharedEventSink = nil
        return nil
    }
}
