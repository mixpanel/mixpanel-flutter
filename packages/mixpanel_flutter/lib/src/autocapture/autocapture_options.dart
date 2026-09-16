/// Options for automatic clicks and frustration signals.
///
/// Omit these options from Mixpanel.init to disable automatic capture. All three
/// signals default to enabled when options are supplied. Distances are logical
/// pixels, independent of device density.
///
/// **Experimental (beta).** Autocapture may contain issues, and its API and the
/// properties it captures may change in a future release before general
/// availability. Pin your SDK version if you build reports on autocaptured events.
class AutocaptureOptions {
  const AutocaptureOptions({
    this.click = true,
    this.rageClick = true,
    this.deadClick = true,
    int rageClickThreshold = 4,
    int rageClickWindowMs = 1000,
    double rageClickRadius = 44,
    int deadClickTimeoutMs = 500,
  })  : _threshold = rageClickThreshold,
        _window = rageClickWindowMs,
        _radius = rageClickRadius,
        _timeout = deadClickTimeoutMs;

  final bool click;
  final bool rageClick;
  final bool deadClick;
  final int _threshold;
  final int _window;
  final double _radius;
  final int _timeout;

  /// Count clamped to 2–100, bounding the supported burst size.
  int get rageClickThreshold => _threshold.clamp(2, 100);

  /// Window clamped to 1–60000 ms to bound retained history.
  int get rageClickWindowMs => _window.clamp(1, 60000);

  /// Nonfinite values use 44; negative radii use zero.
  double get rageClickRadius =>
      _radius.isFinite ? _radius.clamp(0, 100000) : 44;

  /// Response deadline clamped to 1–60000 ms.
  int get deadClickTimeoutMs => _timeout.clamp(1, 60000);

  bool get isEnabled => click || rageClick || deadClick;
}
