import Flutter
import UIKit

public class MixpanelSessionReplayPlugin: NSObject, FlutterPlugin {
    private static let backgroundQueue = DispatchQueue(
        label: "com.mixpanel.flutter_session_replay.compression",
        qos: .userInitiated
    )

    /// Background task identifier for extending execution time during flush
    private var backgroundTaskId = UIBackgroundTaskIdentifier.invalid

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.mixpanel.flutter_session_replay",
            binaryMessenger: registrar.messenger()
        )
        let instance = MixpanelSessionReplayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private static let registerNotificationName = Notification.Name("com.mixpanel.properties.register")
    private static let unregisterNotificationName = Notification.Name("com.mixpanel.properties.unregister")

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "compressImage":
            compressImage(call: call, result: result)
        case "disposeCache":
            result(nil)
        case "registerSuperProperties":
            registerSuperProperties(call: call)
            result(nil)
        case "unregisterSuperProperty":
            unregisterSuperProperty(call: call)
            result(nil)
        case "beginBackgroundTask":
            beginBackgroundTask()
            result(nil)
        case "endBackgroundTask":
            endBackgroundTask()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func beginBackgroundTask() {
        guard let application = UIApplication.value(forKey: "sharedApplication") as? UIApplication else {
            return
        }

        backgroundTaskId = application.beginBackgroundTask { [weak self] in
            // Expiration handler — OS is about to suspend, clean up
            guard let self = self else { return }
            if self.backgroundTaskId != UIBackgroundTaskIdentifier.invalid {
                application.endBackgroundTask(self.backgroundTaskId)
                self.backgroundTaskId = UIBackgroundTaskIdentifier.invalid
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != UIBackgroundTaskIdentifier.invalid else { return }
        guard let application = UIApplication.value(forKey: "sharedApplication") as? UIApplication else {
            return
        }
        application.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = UIBackgroundTaskIdentifier.invalid
    }

    private func registerSuperProperties(call: FlutterMethodCall) {
        guard let data = call.arguments as? [AnyHashable: Any] else { return }
        NotificationCenter.default.post(
            name: MixpanelSessionReplayPlugin.registerNotificationName,
            object: nil,
            userInfo: data
        )
    }

    private func unregisterSuperProperty(call: FlutterMethodCall) {
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else { return }
        NotificationCenter.default.post(
            name: MixpanelSessionReplayPlugin.unregisterNotificationName,
            object: nil,
            userInfo: [key: ""]
        )
    }

    private func compressImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rgbaData = args["rgbaBytes"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int,
              let quality = args["quality"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing required arguments", details: nil))
            return
        }

        let rgbaBytes = rgbaData.data
        let expectedSize = width * height * 4
        guard rgbaBytes.count == expectedSize else {
            result(FlutterError(
                code: "INVALID_DATA",
                message: "Expected \(expectedSize) bytes, got \(rgbaBytes.count)",
                details: nil
            ))
            return
        }

        MixpanelSessionReplayPlugin.backgroundQueue.async {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            // noneSkipLast: treat RGBA as RGBx — ignore the alpha byte (screenshots are fully opaque)
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)

            guard let provider = CGDataProvider(data: rgbaBytes as CFData),
                  let cgImage = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo,
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                  ) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_ERROR", message: "Failed to create CGImage", details: nil))
                }
                return
            }

            let uiImage = UIImage(cgImage: cgImage)

            guard let data = uiImage.jpegData(compressionQuality: CGFloat(quality) / 100.0) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "COMPRESSION_ERROR", message: "JPEG compression failed", details: nil))
                }
                return
            }

            DispatchQueue.main.async {
                result(FlutterStandardTypedData(bytes: data))
            }
        }
    }
}
