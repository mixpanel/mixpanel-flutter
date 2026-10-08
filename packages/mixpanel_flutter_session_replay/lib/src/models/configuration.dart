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

/// Controls what happens to an active replay when a native app leaves the
/// foreground. Set through [MobileOptions.onBackground].
///
/// No replay capture occurs while the app is in the background. Web has no
/// equivalent option: see [WebOptions].
sealed class ReplayBackgroundBehavior {
  const ReplayBackgroundBehavior();

  /// Retain the current replay for up to [idleTimeout].
  const factory ReplayBackgroundBehavior.pause({
    required Duration idleTimeout,
  }) = ReplayBackgroundPauseBehavior;

  /// Stop the current replay when the app leaves the foreground.
  static const stop = ReplayBackgroundStopBehavior();
}

/// Retains the current replay while the app is backgrounded.
final class ReplayBackgroundPauseBehavior extends ReplayBackgroundBehavior {
  const ReplayBackgroundPauseBehavior({required this.idleTimeout});

  /// Maximum time the replay can remain paused before a new replay is started.
  final Duration idleTimeout;
}

/// Stops the current replay when the app is backgrounded.
final class ReplayBackgroundStopBehavior extends ReplayBackgroundBehavior {
  const ReplayBackgroundStopBehavior();
}

/// Mobile-specific configuration options
///
/// These options only apply to iOS and Android platforms.
class MobileOptions {
  const MobileOptions({
    this.wifiOnly = true,
    this.onBackground = ReplayBackgroundBehavior.stop,
  });

  /// Only upload on WiFi (default: true)
  ///
  /// When enabled, session replay data will only be uploaded when the device
  /// is connected to WiFi or Ethernet. Data is queued locally until a WiFi
  /// connection is available.
  final bool wifiOnly;

  /// Behavior when the app leaves the foreground (default: stop).
  ///
  /// The default preserves the SDK's existing native lifecycle behavior.
  final ReplayBackgroundBehavior onBackground;
}

/// Web-specific configuration options
///
/// These options only apply to the web platform (Flutter web).
///
/// As in mixpanel-js, a replay is not affected by the page being hidden or
/// the window losing focus: it continues across tab switches and ends only
/// through [idleTimeout] or [maxSessionDuration]. Nothing is captured while
/// the page is hidden, because Flutter does not render then.
class WebOptions {
  const WebOptions({
    this.idleTimeout = const Duration(minutes: 30),
    this.maxSessionDuration = const Duration(hours: 24),
  });

  /// Duration of user inactivity before the session is ended (default: 30 min).
  ///
  /// Reset by user input only (pointer, keyboard, wheel, trackpad), never by
  /// screen changes, matching mixpanel-js: a screen that repaints on its own
  /// still idles out.
  /// When the timeout fires, the replay ends, and the next user interaction
  /// starts a new one. As in mixpanel-js, the new replay is not sampled
  /// again, so a replay started with `startRecording()` also restarts.
  /// Overridden by a valid remote `record_idle_timeout_ms` when remote
  /// settings are enabled.
  ///
  /// Set to [Duration.zero] to disable idle timeout.
  final Duration idleTimeout;

  /// Maximum total duration of a single session (default: 24 hours).
  ///
  /// Hard cap regardless of user activity. When exceeded, the current session
  /// ends and a new session starts on the next user interaction, without
  /// sampling again.
  /// Overridden by a valid remote `record_max_ms` when remote settings are
  /// enabled.
  final Duration maxSessionDuration;
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
