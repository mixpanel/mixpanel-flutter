import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../internal/widget_coordinator.dart';
import '../internal/capture/capture_scheduler.dart';
import '../internal/settings/settings_service.dart';
import '../models/debug_overlay_colors.dart';
import '../models/masking_directive.dart';
import '../models/results.dart';
import 'mask_overlay.dart';

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

  @override
  void initState() {
    super.initState();

    // Create timing scheduler (private to this widget)
    _scheduler = CaptureScheduler(logger: widget.coordinator.logger);

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

    final boundary = _repaintBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;

    // Tell scheduler we're starting
    _scheduler.markCaptureStarted();

    // Simple call to coordinator (like interactions)
    widget.coordinator.captureSnapshot(boundary).whenComplete(() {
      if (mounted) {
        // Tell scheduler we completed (500ms starts now)
        // This runs whether capture succeeded or failed, ensuring we always
        // wait 500ms before the next attempt (prevents excessive retries on failure)
        _scheduler.markCaptureCompleted();
      }
    });
  }

  @override
  void dispose() {
    widget.frameNotifier.removeListener(_onFrame);
    _scheduler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = RepaintBoundary(
      key: _repaintBoundaryKey,
      child: widget.child,
    );

    // Conditionally wrap with mask overlay for debugging (only in debug mode)
    final overlayColors = widget.debugOptions?.overlayColors;
    if (overlayColors != null && kDebugMode) {
      child = ValueListenableBuilder<List<MaskRegionInfo>>(
        valueListenable: widget.coordinator.maskRegionsNotifier,
        builder: (context, maskRegions, child) {
          return MaskOverlay(
            maskRegions: maskRegions,
            colors: overlayColors,
            child: child!,
          );
        },
        child: child,
      );
    }

    return child;
  }
}
