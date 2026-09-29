import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../internal/widget_coordinator.dart';
import '../internal/capture/capture_scheduler.dart';
import '../internal/debug_mask_overlay.dart';
import '../internal/settings/settings_service.dart';
import '../models/debug_overlay_colors.dart';
import '../models/results.dart';

/// Internal widget that monitors frame changes and schedules snapshots
class FrameMonitor extends StatefulWidget {
  const FrameMonitor({
    super.key,
    required this.frameNotifier,
    required this.coordinator,
    required this.child,
    this.debugOptions,
  });

  final ChangeNotifier frameNotifier;
  final WidgetCoordinator coordinator;
  final Widget child;
  final DebugOptions? debugOptions;

  @override
  State<FrameMonitor> createState() => _FrameMonitorState();
}

class _FrameMonitorState extends State<FrameMonitor> {
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  late final CaptureScheduler _scheduler;

  /// Debug mask overlay, drawn wherever the coordinator's capture cannot see
  /// it. Null unless the overlay is enabled.
  DebugMaskOverlay? _debugOverlay;

  @override
  void initState() {
    super.initState();

    // Create timing scheduler (private to this widget)
    _scheduler = CaptureScheduler(logger: widget.coordinator.logger);

    final overlayColors = widget.debugOptions?.overlayColors;
    if (kDebugMode && overlayColors != null) {
      _debugOverlay = widget.coordinator.createDebugMaskOverlay(
        regions: widget.coordinator.maskRegionsNotifier,
        colors: overlayColors,
        boundary: () {
          final boundary = _repaintBoundaryKey.currentContext
              ?.findRenderObject();
          return boundary is RenderBox ? boundary : null;
        },
      );
    }

    // Listen to frame notifications from parent widget
    widget.frameNotifier.addListener(_onFrame);

    // Schedule initial capture after first frame completes
    // This ensures we capture even if UI becomes static after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptCapture();
    });
  }

  void _onFrame() {
    if (!mounted) return;

    _debugOverlay?.onFrame();

    // Skip processing if remotely disabled
    if (widget.coordinator.remoteEnablementState ==
        RemoteEnablementState.disabled) {
      return;
    }

    // Skip processing if recording is not active
    if (widget.coordinator.recordingState != RecordingState.recording) return;

    // Skip processing if app is not in foreground
    // (Lifecycle state is tracked by LifecycleObserver and exposed via coordinator)
    if (!widget.coordinator.isAppInForeground) return;

    // UI changed (frame rendered) - attempt to capture
    _attemptCapture();
  }

  void _attemptCapture() {
    // Skip processing if remotely disabled
    if (widget.coordinator.remoteEnablementState ==
        RemoteEnablementState.disabled) {
      return;
    }

    // Skip processing if recording is not active
    if (widget.coordinator.recordingState != RecordingState.recording) return;

    // Skip processing if app is not in foreground
    // (Lifecycle state is tracked by LifecycleObserver and exposed via coordinator)
    if (!widget.coordinator.isAppInForeground) return;

    // Ask scheduler: "Can I capture now?"
    if (_scheduler.canCapture()) {
      _triggerCapture();
    } else {
      // Ask scheduler to schedule a deferred capture if needed
      // Scheduler is smart: won't schedule if timer already pending
      _scheduler.scheduleAfterRateLimit(_triggerCapture);
    }
  }

  void _triggerCapture() {
    if (!mounted) return;

    // Skip if remotely disabled (handles scheduled captures from before settings check)
    if (widget.coordinator.remoteEnablementState ==
        RemoteEnablementState.disabled) {
      return;
    }

    // Skip if recording is not active (handles scheduled captures from before stop)
    if (widget.coordinator.recordingState != RecordingState.recording) return;

    // Double-check we can capture (prevents race condition between timer and frame callbacks)
    if (!_scheduler.canCapture()) return;

    // Tell scheduler we're starting
    _scheduler.markCaptureStarted();
    unawaited(_runCapture());
  }

  Future<void> _runCapture() async {
    try {
      await _captureCurrentBoundary();
    } finally {
      if (mounted) {
        // The 500 ms rate limit starts whether capture succeeded or failed.
        _scheduler.markCaptureCompleted();
        // A frame that rendered while this capture ran may show the settled
        // screen, and a static screen produces no further frames. Attempt one
        // rate-limited follow-up; the usual recording and foreground checks
        // still apply when it fires.
        if (_scheduler.takeFrameArrivedDuringCapture()) _attemptCapture();
      }
    }
  }

  Future<void> _captureCurrentBoundary() async {
    final boundaryElement = _repaintBoundaryKey.currentContext;
    if (boundaryElement is! Element) return;
    final boundary = boundaryElement.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    await widget.coordinator.captureSnapshot(
      boundary,
      boundaryElement: boundaryElement,
      onRenderTreeRead: _scheduler.markRenderTreeRead,
    );
  }

  @override
  void dispose() {
    widget.frameNotifier.removeListener(_onFrame);
    _debugOverlay?.dispose();
    _scheduler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = RepaintBoundary(
      key: _repaintBoundaryKey,
      child: widget.child,
    );
    return _debugOverlay?.wrap(child) ?? child;
  }
}
