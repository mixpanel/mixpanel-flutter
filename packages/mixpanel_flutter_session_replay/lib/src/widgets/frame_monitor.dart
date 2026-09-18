import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../internal/widget_coordinator.dart';
import '../internal/capture/capture_scheduler.dart';
import '../internal/platform/debug_overlay_host.dart';
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

  /// True where capture reads a shared rendered surface (web) rather than this
  /// widget's [RepaintBoundary]. The overlay widget would be captured there, so
  /// it is drawn outside the Flutter surface by [_debugOverlayHost] instead.
  late final bool _capturesRenderedSurface;
  DebugOverlayHost? _debugOverlayHost;

  @override
  void initState() {
    super.initState();

    // Create timing scheduler (private to this widget)
    _scheduler = CaptureScheduler(logger: widget.coordinator.logger);

    _capturesRenderedSurface = widget.coordinator.capturesRenderedSurface;
    if (_capturesRenderedSurface && _debugOverlayEnabled) {
      _debugOverlayHost = createDebugOverlayHost();
    }
    if (_debugOverlayHost != null) {
      widget.coordinator.maskRegionsNotifier.addListener(_onMaskRegionsChanged);
      // The notifier only fires on change, and the coordinator suppresses a
      // capture whose regions match the stored ones. Paint the current value
      // once so a host attached to an already-populated notifier is not blank
      // until the layout happens to move.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onMaskRegionsChanged();
      });
    }

    // Listen to frame notifications from parent widget
    widget.frameNotifier.addListener(_onFrame);

    // Schedule initial capture after first frame completes
    // This ensures we capture even if UI becomes static after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptCapture();
    });
  }

  bool get _debugOverlayEnabled =>
      kDebugMode && widget.debugOptions?.overlayColors != null;

  /// Redraws the out-of-surface overlay. Touching the DOM directly keeps this
  /// off Flutter's build pipeline, so the overlay cannot schedule the frame
  /// that would trigger the next capture.
  void _onMaskRegionsChanged() {
    final host = _debugOverlayHost;
    final colors = widget.debugOptions?.overlayColors;
    if (host == null || colors == null) return;
    final boundary = _repaintBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderBox || !boundary.hasSize) return;
    host.update(
      regions: widget.coordinator.maskRegionsNotifier.value,
      colors: colors,
      boundaryOrigin: boundary.localToGlobal(Offset.zero),
      boundarySize: boundary.size,
    );
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
    );
  }

  @override
  void dispose() {
    widget.frameNotifier.removeListener(_onFrame);
    // Unconditional: removeListener is a no-op for a listener never added, so
    // this cannot desync from the registration condition above.
    widget.coordinator.maskRegionsNotifier.removeListener(
      _onMaskRegionsChanged,
    );
    _debugOverlayHost?.dispose();
    _scheduler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = RepaintBoundary(
      key: _repaintBoundaryKey,
      child: widget.child,
    );

    // Conditionally wrap with mask overlay for debugging (only in debug mode).
    // Skipped where capture reads the rendered surface — the overlay would end
    // up in the replay, so it is drawn outside that surface instead. Skipped
    // there even when no host could be created, so the diagnostic paint can
    // never leak into an upload.
    final overlayColors = widget.debugOptions?.overlayColors;
    if (overlayColors != null && kDebugMode && !_capturesRenderedSurface) {
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
