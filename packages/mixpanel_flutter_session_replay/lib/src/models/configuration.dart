/// Widget types that can be automatically masked
enum AutoMaskedView {
  /// Text widgets (Text, TextField, CupertinoTextField, EditableText)
  text,

  /// Image widgets (via RenderImage detection)
  image,
}

/// Controls how the SDK handles remote settings from the Mixpanel settings endpoint.
///
/// Remote settings enable server-side control over session replay parameters such as
/// sampling rate. This enum determines the SDK's behavior when fetching these
/// settings and how failures are handled.
///
/// | Mode       | Config Applied | On Failure                      |
/// |------------|----------------|----------------------------------|
/// | `disabled` | No             | Uses local config                |
/// | `strict`   | Yes            | No replays sent                  |
/// | `fallback` | Yes            | Uses cache or local config       |
enum RemoteSettingsMode {
  /// Remote SDK config is not applied.
  ///
  /// The SDK initializes using only the app-provided configuration.
  /// Remote config values (e.g., `record_sessions_percent`) are ignored.
  disabled,

  /// Requires successful remote SDK config fetch for recording.
  ///
  /// If the network request fails, times out, or the response does not include
  /// `sdk_config.config`, recording is disabled and **no replays are sent**.
  strict,

  /// Attempts remote fetch with graceful degradation on failure.
  ///
  /// On success, remote settings are applied and cached locally. If the fetch
  /// fails or times out, the SDK initializes using:
  /// 1. Previously cached remote settings (from last successful fetch)
  /// 2. App-provided configuration (if no cache exists)
  fallback,
}

/// Log level for SDK logging
enum LogLevel {
  /// No logging
  none,

  /// Error messages only
  error,

  /// Warning and error messages
  warning,

  /// Info, warning, and error messages
  info,

  /// Debug and all other messages (verbose)
  debug,
}

/// Mobile-specific configuration options
///
/// These options only apply to iOS and Android platforms.
class MobileOptions {
  const MobileOptions({this.wifiOnly = true});

  /// Only upload on WiFi (default: true)
  ///
  /// When enabled, session replay data will only be uploaded when the device
  /// is connected to WiFi or Ethernet. Data is queued locally until a WiFi
  /// connection is available.
  final bool wifiOnly;
}

/// How Flutter web captures a frame that contains an HTML platform view.
enum WebPlatformViewCapturePolicy {
  /// Replace the complete replay frame with the standard privacy mask.
  ///
  /// Flutter's canvas and the browser-managed platform view are separate
  /// surfaces, so their pixels cannot be combined and masked atomically.
  /// Masking the complete frame is the privacy-safe default.
  maskEntireFrame,

  /// Capture the Flutter canvas normally without adding a platform-view mask.
  ///
  /// The HTML platform view itself is not guaranteed to appear in the captured
  /// image. Use this only when the application has independently established
  /// that the platform view cannot expose sensitive information.
  captureNormally,
}

/// Web-specific configuration options
///
/// These options only apply to the web platform (Flutter web).
class WebOptions {
  const WebOptions({
    this.idleTimeout = const Duration(minutes: 30),
    this.maxSessionDuration = const Duration(hours: 24),
    this.platformViewCapturePolicy =
        WebPlatformViewCapturePolicy.maskEntireFrame,
  });

  /// Duration of user inactivity before the session is ended (default: 30 min).
  ///
  /// Reset on every user interaction or screenshot capture.
  /// When the timeout fires, recording stops and a new session starts
  /// on the next user interaction.
  ///
  /// Set to [Duration.zero] to disable idle timeout.
  final Duration idleTimeout;

  /// Maximum total duration of a single session (default: 24 hours).
  ///
  /// Hard cap regardless of user activity. When exceeded, the current session
  /// ends and a new session starts on the next user interaction.
  final Duration maxSessionDuration;

  /// Privacy behavior when a frame contains an HTML platform view.
  final WebPlatformViewCapturePolicy platformViewCapturePolicy;
}

/// Platform-specific configuration options
///
/// Use this to configure options that only apply to specific platforms.
///
/// Example:
/// ```dart
/// SessionReplayOptions(
///   logLevel: LogLevel.debug,
///   platformOptions: PlatformOptions(
///     mobile: MobileOptions(wifiOnly: true),
///     web: WebOptions(idleTimeout: Duration(minutes: 15)),
///   ),
/// )
/// ```
class PlatformOptions {
  const PlatformOptions({
    this.mobile = const MobileOptions(),
    this.web = const WebOptions(),
  });

  /// Mobile-specific options (iOS and Android)
  final MobileOptions mobile;

  /// Web-specific options (Flutter web)
  final WebOptions web;
}
