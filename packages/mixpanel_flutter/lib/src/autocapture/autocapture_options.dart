/// Options for automatic clicks and frustration signals.
///
/// Omit from Mixpanel.init to disable automatic capture. Each signal defaults
/// to enabled when options are supplied.
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
    this.clickThreshold = 4,
    this.timeWindow = const Duration(seconds: 1),
    this.radius = 44,
  })  : assert(clickThreshold >= 2 && clickThreshold <= 100),
        assert(radius >= 0 && radius <= 100000);

  final bool enabled;

  /// Number of taps required, between 2 and 100. Defaults to 4.
  final int clickThreshold;

  /// Rolling window, between 1 ms and 1 minute. Defaults to 1 second.
  final Duration timeWindow;

  /// Finite radius in logical pixels, between 0 and 100000. Defaults to 44.
  final double radius;
}

/// Configuration for dead-click detection.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class DeadClickOptions {
  const DeadClickOptions({
    this.enabled = true,
    this.timeWindow = const Duration(milliseconds: 500),
  });

  final bool enabled;

  /// Response deadline, between 1 ms and 1 minute. Defaults to 500 ms.
  final Duration timeWindow;
}
