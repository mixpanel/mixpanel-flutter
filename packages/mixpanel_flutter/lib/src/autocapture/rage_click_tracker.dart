import 'autocapture_options.dart';
import 'detection_limits.dart';

/// Android-compatible rolling spatial window. Internal to automatic capture.
class RageClickTracker {
  RageClickTracker(this.options) {
    assert(validTimeWindow(options.timeWindow));
  }
  final RageClickOptions options;
  final List<_Tap> _taps = [];

  bool record(double x, double y, Duration time) {
    if (!x.isFinite || !y.isFinite) return false;
    final cutoff = time - normalizeTimeWindow(options.timeWindow);
    _taps.removeWhere((tap) => tap.time < cutoff);
    // A backwards timestamp invalidates a sequence instead of extending it.
    if (_taps.isNotEmpty && time < _taps.last.time) reset();
    // Under overload, drop the uncertain history. Never retain unbounded data.
    if (_taps.length >= 512) reset();
    _taps.add(_Tap(x, y, time));
    final radius = normalizeRadius(options.radius);
    final radiusSquared = radius * radius;
    var count = 0;
    for (final tap in _taps) {
      final dx = tap.x - x;
      final dy = tap.y - y;
      if (dx * dx + dy * dy <= radiusSquared) count++;
    }
    if (count < normalizeClickThreshold(options.clickThreshold)) return false;
    reset();
    return true;
  }

  void reset() => _taps.clear();
}

class _Tap {
  const _Tap(this.x, this.y, this.time);
  final double x;
  final double y;
  final Duration time;
}
