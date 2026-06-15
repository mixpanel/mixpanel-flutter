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
///   ),
/// )
/// ```
class PlatformOptions {
  const PlatformOptions({this.mobile = const MobileOptions()});

  /// Mobile-specific options (iOS and Android)
  final MobileOptions mobile;
}
