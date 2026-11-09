import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Synchronizes skwasm surface reads with Flutter's completed raster frames.
///
/// A completed Dart paint does not mean the asynchronous skwasm renderer has
/// updated the canvas. Its frame timing report is submitted after that update.
/// Frame numbers connect that acknowledgement to the tree used to read masks.
/// This assumes a single Flutter view, as enforced by web surface discovery.
class RasterCompletionBarrier {
  static const _timeout = Duration(milliseconds: 500);

  // Web batches timing reports at roughly 100 ms, and a static screen may
  // need another rendered frame to deliver the batch. This delay only prompts
  // delivery; elapsed time is never treated as proof of raster completion.
  static const _reportingFrameDelay = Duration(milliseconds: 120);

  final SchedulerBinding _binding = SchedulerBinding.instance;
  final Set<_RasterWait> _waits = {};
  int _lastRasterizedFrame = -1;
  bool _disposed = false;

  RasterCompletionBarrier() {
    _binding.addTimingsCallback(_onTimings);
  }

  /// Requests a fresh frame and waits for its raster acknowledgement.
  ///
  /// Call before reading masks. Any reporting frame requested here must finish
  /// before that read so it cannot re-arm the capture scheduler on a static
  /// screen. The deadline also covers waiting for the fresh Flutter frame.
  Future<bool> prepare() {
    if (_disposed) return Future.value(false);
    final wait = _newWait();
    _awaitFreshFrame(wait);
    return wait.result.future;
  }

  void _awaitFreshFrame(_RasterWait wait) {
    // A previously requested frame may finish rasterizing after we request a
    // reporting frame but before that frame paints. Do not let its report
    // release preparation while our own frame is still scheduled.
    wait.frameNumber = null;
    _binding.endOfFrame.then((_) {
      if (wait.isCompleted) return;
      _observeCurrentFrame(wait);
      if (!wait.isCompleted) {
        wait.reportingFrame = Timer(_reportingFrameDelay, () {
          if (!wait.isCompleted) _awaitFreshFrame(wait);
        });
      }
    });
  }

  /// Pins the current frame synchronously, immediately after the mask walk.
  ///
  /// Newer acknowledgements also qualify because skwasm can drop queued
  /// frames. The caller must still validate masks after taking the snapshot.
  /// No frames are requested here: doing so after the mask walk would cause
  /// the capture scheduler to keep scheduling follow-up captures.
  Future<bool> waitForCurrentFrame() {
    if (_disposed) return Future.value(false);
    final wait = _newWait();
    _observeCurrentFrame(wait);
    return wait.result.future;
  }

  _RasterWait _newWait() {
    final wait = _RasterWait();
    _waits.add(wait);
    wait.deadline = Timer(_timeout, () => _finish(wait, false));
    return wait;
  }

  void _observeCurrentFrame(_RasterWait wait) {
    wait.frameNumber = _binding.platformDispatcher.frameData.frameNumber;
    if (wait.frameNumber! < 0) {
      _finish(wait, false);
      return;
    }
    if (_lastRasterizedFrame >= wait.frameNumber!) _finish(wait, true);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      if (timing.frameNumber > _lastRasterizedFrame) {
        _lastRasterizedFrame = timing.frameNumber;
      }
    }
    for (final wait in _waits.toList()) {
      if (wait.frameNumber case final frame?) {
        if (_lastRasterizedFrame >= frame) _finish(wait, true);
      }
    }
  }

  void _finish(_RasterWait wait, bool acknowledged) {
    if (wait.isCompleted) return;
    wait.deadline?.cancel();
    wait.reportingFrame?.cancel();
    _waits.remove(wait);
    wait.result.complete(acknowledged);
  }

  /// Removes the listener and rejects pending waits without requesting frames.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _binding.removeTimingsCallback(_onTimings);
    for (final wait in _waits.toList()) {
      _finish(wait, false);
    }
  }
}

class _RasterWait {
  final result = Completer<bool>();
  int? frameNumber;
  Timer? deadline;
  Timer? reportingFrame;

  bool get isCompleted => result.isCompleted;
}
