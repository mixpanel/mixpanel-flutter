import Cocoa
import FlutterMacOS
import ImageIO

public class MixpanelSessionReplayPlugin: NSObject, FlutterPlugin {
    private static let backgroundQueue = DispatchQueue(
        label: "com.mixpanel.flutter_session_replay.compression",
        qos: .userInitiated
    )

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.mixpanel.flutter_session_replay",
            binaryMessenger: registrar.messenger
        )
        let instance = MixpanelSessionReplayPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "compressImage":
            compressImage(call: call, result: result)
        case "disposeCache":
            result(nil)
        case "beginBackgroundTask":
            result(nil)
        case "endBackgroundTask":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
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

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: CGFloat(quality) / 100.0
            ]

            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "COMPRESSION_ERROR", message: "JPEG compression failed", details: nil))
                }
                return
            }
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "COMPRESSION_ERROR", message: "JPEG compression failed", details: nil))
                }
                return
            }

            DispatchQueue.main.async {
                result(FlutterStandardTypedData(bytes: data as Data))
            }
        }
    }
}
