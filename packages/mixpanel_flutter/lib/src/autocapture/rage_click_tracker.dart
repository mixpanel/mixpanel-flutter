import 'autocapture_options.dart';
import 'detection_limits.dart';

/// Rolling spatial window of recent taps. Internal to automatic capture.
class RageClickTracker {
  RageClickTracker(RageClickOptions options)
      : _window = normalizeTimeWindow(options.timeWindow),
        _threshold = normalizeClickThreshold(options.clickThreshold),
        _radiusSquared =
            normalizeRadius(options.radius) * normalizeRadius(options.radius) {
    assert(validTimeWindow(options.timeWindow));
  }
  final Duration _window;
  final int _threshold;
  final double _radiusSquared;
  final List<_Tap> _taps = [];

  bool record(double x, double y, Duration time) {
    if (!x.isFinite || !y.isFinite) return false;
    final cutoff = time - _window;
    _taps.removeWhere((tap) => tap.time < cutoff);
    // A backwards timestamp invalidates a sequence instead of extending it.
    if (_taps.isNotEmpty && time < _taps.last.time) reset();
    // Under overload, drop the uncertain history. Never retain unbounded data.
    if (_taps.length >= 512) reset();
    _taps.add(_Tap(x, y, time));
    var count = 0;
    for (final tap in _taps) {
      final dx = tap.x - x;
      final dy = tap.y - y;
      if (dx * dx + dy * dy <= _radiusSquared) count++;
    }
    if (count < _threshold) return false;
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
