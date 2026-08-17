import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';

/// Receives [DebugOptions.wireframeEmitter] snapshots so a tester can inspect
/// what wireframe capture is actually sending, on device, without a console.
///
/// Only the most recent snapshot is kept. Frames arrive up to twice a second
/// and each one is the whole screen, so retaining history would cost far more
/// than it tells you — the interesting question is always "what does the
/// screen I am looking at right now emit?".
class WireframeModel extends ChangeNotifier {
  WireframeSnapshot? _latest;
  int _snapshotCount = 0;
  Timer? _batchNotifyTimer;
  bool _hasPendingNotification = false;

  /// Most recent snapshot, or null if none has been emitted yet.
  WireframeSnapshot? get latest => _latest;

  /// How many snapshots have been received since the last [clear].
  int get snapshotCount => _snapshotCount;

  /// Record a snapshot. Safe to pass directly as the debug emitter.
  void add(WireframeSnapshot snapshot) {
    _latest = snapshot;
    _snapshotCount++;
    _scheduleBatchedNotification();
  }

  void clear() {
    _latest = null;
    _snapshotCount = 0;
    notifyListeners();
  }

  /// Coalesce rebuilds — snapshots arrive far faster than a human reads them.
  void _scheduleBatchedNotification() {
    if (_hasPendingNotification) return;

    _hasPendingNotification = true;
    _batchNotifyTimer?.cancel();

    _batchNotifyTimer = Timer(const Duration(milliseconds: 500), () {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
        _hasPendingNotification = false;
      });
    });
  }

  @override
  void dispose() {
    _batchNotifyTimer?.cancel();
    super.dispose();
  }
}
