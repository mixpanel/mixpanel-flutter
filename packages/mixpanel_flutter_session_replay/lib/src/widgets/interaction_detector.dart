import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../internal/widget_coordinator.dart';
import '../internal/settings/settings_service.dart';
import '../models/results.dart';
import '../models/rrweb_types.dart';
import '../models/session_event.dart' show TouchPosition;

/// Internal widget that translates the pointer stream into rrweb touch events.
///
/// A gesture becomes `touchStart` → zero or more `touchMove` position batches →
/// `touchEnd` (or `touchCancel`). Only the primary pointer is tracked, matching
/// rrweb-web; secondary pointers going down or up mid-gesture are ignored.
///
/// Nothing is deferred: batches drain on the next sampled move or when the
/// gesture ends, so no position is held behind a timer.
class InteractionDetector extends StatefulWidget {
  const InteractionDetector({
    super.key,
    required this.coordinator,
    required this.child,
  });

  final WidgetCoordinator coordinator;
  final Widget child;

  @override
  State<InteractionDetector> createState() => _InteractionDetectorState();
}

class _InteractionDetectorState extends State<InteractionDetector> {
  /// Pointer id of the gesture in flight; null when not tracking.
  int? _activePointer;

  /// Positions sampled since the last flush, oldest first.
  final List<_TouchSample> _pendingSamples = [];

  /// `PointerEvent.timeStamp` of the last sampled move, for interval gating.
  Duration _lastSampledTimeStamp = Duration.zero;

  /// Wall clock and pointer-clock readings taken at the gesture's first event.
  ///
  /// `PointerEvent.timeStamp` runs on the engine's monotonic clock, which has
  /// no exposed "now", so a gesture is anchored once and every later event is
  /// projected onto wall clock through the anchor. Re-anchoring per gesture
  /// keeps a device that slept between gestures from skewing the next one,
  /// while preserving exact relative timing within a gesture — which is what
  /// the replay's smoothness depends on.
  DateTime _epochAnchor = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  Duration _timeStampAnchor = Duration.zero;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    // A second finger landing mid-gesture is not the primary pointer.
    if (_activePointer != null) return;

    final coordinator = widget.coordinator;

    // Skip processing if remotely disabled
    if (coordinator.remoteEnablementState == RemoteEnablementState.disabled) {
      return;
    }

    // Skip processing if recording is not active
    if (coordinator.recordingState != RecordingState.recording) return;

    coordinator.logger.debug(
      'Pointer down detected: ${event.kind} at ${event.localPosition}',
    );

    // Only handle primary pointer (finger/mouse) interactions
    if (event.kind != PointerDeviceKind.touch &&
        event.kind != PointerDeviceKind.mouse) {
      coordinator.logger.debug(
        'Ignoring non-touch/mouse pointer: ${event.kind}',
      );
      return;
    }

    coordinator.logger.debug('Capturing interaction');

    _resetGesture();
    _activePointer = event.pointer;
    _epochAnchor = clock.now();
    _timeStampAnchor = event.timeStamp;
    _lastSampledTimeStamp = event.timeStamp;

    coordinator.captureInteraction(
      RRWebMouseInteraction.touchStart,
      event.localPosition,
      _epochAnchor,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    // A move without a preceding down means recording started mid-gesture;
    // wait for the next clean gesture rather than emitting a path with no
    // start.
    if (event.pointer != _activePointer) return;
    if (event.timeStamp - _lastSampledTimeStamp <
        TouchSampling.moveSampleInterval) {
      return;
    }

    _lastSampledTimeStamp = event.timeStamp;
    _pendingSamples.add(
      _TouchSample(
        position: event.localPosition,
        timeStamp: event.timeStamp,
        wallClock: _toWallClock(event.timeStamp),
      ),
    );

    final batchSpan =
        _pendingSamples.last.timeStamp - _pendingSamples.first.timeStamp;
    if (batchSpan >= TouchSampling.moveBatchInterval ||
        _pendingSamples.length >= TouchSampling.maxPositionsPerBatch) {
      _flushSamples();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _endGesture(event, RRWebMouseInteraction.touchEnd);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _endGesture(event, RRWebMouseInteraction.touchCancel);
  }

  void _endGesture(PointerEvent event, int interactionType) {
    if (event.pointer != _activePointer) return;

    // Drain the path before the boundary event so the stream stays
    // chronological.
    _flushSamples();
    widget.coordinator.captureInteraction(
      interactionType,
      event.localPosition,
      _toWallClock(event.timeStamp),
    );
    _resetGesture();
  }

  void _flushSamples() {
    if (_pendingSamples.isEmpty) return;

    // rrweb replays a sample at `event.timestamp + timeOffset`, so the batch is
    // stamped with its final sample and every offset is <= 0.
    final batchTime = _pendingSamples.last.wallClock;
    final positions = _pendingSamples
        .map(
          (s) => TouchPosition(
            x: s.position.dx,
            y: s.position.dy,
            timeOffset: s.wallClock.difference(batchTime).inMilliseconds,
          ),
        )
        .toList(growable: false);
    _pendingSamples.clear();

    widget.coordinator.captureTouchMove(positions, batchTime);
  }

  void _resetGesture() {
    _pendingSamples.clear();
    _activePointer = null;
    _lastSampledTimeStamp = Duration.zero;
  }

  DateTime _toWallClock(Duration timeStamp) =>
      _epochAnchor.add(timeStamp - _timeStampAnchor);
}

/// A sampled drag position, held until the batch it belongs to is flushed.
class _TouchSample {
  const _TouchSample({
    required this.position,
    required this.timeStamp,
    required this.wallClock,
  });

  /// Position in logical pixels, same coordinate space as the screenshots.
  final Offset position;

  /// Engine monotonic clock reading, used for sampling and batch-span gating.
  final Duration timeStamp;

  /// [timeStamp] projected onto wall clock through the gesture's anchor.
  final DateTime wallClock;
}
