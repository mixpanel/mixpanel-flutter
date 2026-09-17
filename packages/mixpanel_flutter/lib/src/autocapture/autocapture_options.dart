/// Options for automatic clicks and frustration signals.
///
/// Omit from Mixpanel.init to disable automatic capture. Each signal defaults
/// to enabled when options are supplied, matching the native SDK structure.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class AutocaptureOptions {
  const AutocaptureOptions({
    this.clickOptions = const ClickOptions(),
    this.rageClickOptions = const RageClickOptions(),
    this.deadClickOptions = const DeadClickOptions(),
  });

  final ClickOptions clickOptions;
  final RageClickOptions rageClickOptions;
  final DeadClickOptions deadClickOptions;

  bool get isEnabled =>
      clickOptions.enabled ||
      rageClickOptions.enabled ||
      deadClickOptions.enabled;
}

/// Configuration for basic click capture.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class ClickOptions {
  const ClickOptions({this.enabled = true});

  /// Whether basic click events are emitted. Defaults to true.
  final bool enabled;
}

/// Configuration for rage-click detection. Distances use logical pixels.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class RageClickOptions {
  const RageClickOptions({
    this.enabled = true,
    int clickThreshold = 4,
    int timeWindowMs = 1000,
    double radius = 44,
  })  : _threshold = clickThreshold,
        _window = timeWindowMs,
        _radius = radius;

  final bool enabled;
  final int _threshold;
  final int _window;
  final double _radius;

  /// Number of taps required. Defaults to 4; clamped to 2–100.
  int get clickThreshold => _threshold.clamp(2, 100);

  /// Rolling window. Defaults to 1000 ms; clamped to 1–60000 ms.
  int get timeWindowMs => _window.clamp(1, 60000);

  /// Radius in logical pixels. Defaults to 44. Nonfinite values use 44;
  /// finite values are clamped to 0–100000.
  double get radius => _radius.isFinite ? _radius.clamp(0, 100000) : 44;
}

/// Configuration for dead-click detection.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class DeadClickOptions {
  const DeadClickOptions({this.enabled = true, int timeWindowMs = 500})
      : _window = timeWindowMs;

  final bool enabled;
  final int _window;

  /// Response deadline. Defaults to 500 ms; clamped to 1–60000 ms.
  int get timeWindowMs => _window.clamp(1, 60000);
}
