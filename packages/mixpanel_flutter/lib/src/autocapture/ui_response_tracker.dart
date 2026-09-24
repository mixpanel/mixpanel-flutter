import 'package:flutter/widgets.dart';
import 'capture_frame_observer.dart';
import 'response_snapshot.dart';

/// A response, once observed, stays observed even if the UI returns to baseline.
class ResponseObservation {
  ResponseObservation(this.baseline)
      : change = baseline == null
            ? ResponseChange.unknown
            : ResponseChange.unchanged;
  final ResponseSnapshot? baseline;
  ResponseChange change;
  ResponseSnapshot? get unchangedBaseline =>
      change == ResponseChange.unchanged ? baseline : null;

  void sample(ResponseSnapshot? current) {
    if (change != ResponseChange.unchanged) return;
    change = baseline!.compare(current);
  }

  void markChanged() => change = ResponseChange.changed;
}

/// Owns response subscriptions and the current press observation. The snapshot
/// from a frame is shared with the pending dead candidate through onSnapshot.
class UiResponseTracker with WidgetsBindingObserver {
  UiResponseTracker(
      {required this.capture,
      required this.canObserve,
      required this.hasCandidate,
      required this.onSnapshot,
      required this.onResponse});
  final ResponseSnapshot? Function() capture;
  final bool Function() canObserve;
  final bool Function() hasCandidate;
  final void Function(ResponseSnapshot?) onSnapshot;
  final VoidCallback onResponse;
  ResponseObservation? _press;
  bool _listening = false;

  void beginPress() => _press = ResponseObservation(capture());
  void cancelPress() => _press = null;
  ResponseSnapshot? takeBaseline() {
    final baseline = _press?.unchangedBaseline;
    _press = null;
    return baseline;
  }

  void start() {
    if (_listening) return;
    _listening = true;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(markResponse);
    CaptureFrameObserver.add(sampleFrame, _isObserving);
  }

  void stop() {
    cancelPress();
    if (!_listening) return;
    _listening = false;
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(markResponse);
    CaptureFrameObserver.remove(sampleFrame);
  }

  bool _isObserving() =>
      canObserve() && (hasCandidate() || _press?.unchangedBaseline != null);

  void sampleFrame() {
    if (!_isObserving()) return;
    final current = capture();
    onSnapshot(current);
    _press?.sample(current);
  }

  void markResponse() {
    _press?.markChanged();
    onResponse();
  }

  bool onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      markResponse();
    }
    return false;
  }

  @override
  void didChangeMetrics() => markResponse();
}
