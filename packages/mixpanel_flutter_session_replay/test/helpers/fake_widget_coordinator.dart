import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/widget_coordinator.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart'
    show TouchPosition;

/// Fake implementation of [WidgetCoordinator] for widget tests.
///
/// All state is directly settable and all method calls are recorded
/// for assertion. No SQLite, HTTP, timers, or async I/O involved.
class FakeWidgetCoordinator implements WidgetCoordinator {
  // ── Controllable state ──

  @override
  RecordingState recordingState;

  @override
  RemoteEnablementState remoteEnablementState;

  @override
  bool isAppInForeground;

  @override
  final MixpanelLogger logger;

  @override
  final ValueNotifier<List<MaskRegionInfo>> maskRegionsNotifier;

  // ── Call tracking ──

  int onAppForegroundedCallCount = 0;
  int onAppBackgroundedCallCount = 0;
  int captureSnapshotCallCount = 0;
  final List<({RenderRepaintBoundary boundary, Element boundaryElement})>
  capturedSnapshots = [];

  final List<({int interactionType, Offset position, DateTime timestamp})>
  capturedInteractions = [];

  final List<({List<TouchPosition> positions, DateTime timestamp})>
  capturedTouchMoves = [];

  FakeWidgetCoordinator({
    this.recordingState = RecordingState.notRecording,
    this.remoteEnablementState = RemoteEnablementState.enabled,
    this.isAppInForeground = true,
    MixpanelLogger? logger,
    ValueNotifier<List<MaskRegionInfo>>? maskRegionsNotifier,
  }) : logger = logger ?? MixpanelLogger(LogLevel.none),
       maskRegionsNotifier =
           maskRegionsNotifier ?? ValueNotifier<List<MaskRegionInfo>>([]);

  @override
  void onAppForegrounded() {
    onAppForegroundedCallCount++;
  }

  @override
  void onAppBackgrounded() {
    onAppBackgroundedCallCount++;
  }

  @override
  void captureInteraction(
    int interactionType,
    Offset position,
    DateTime timestamp,
  ) {
    capturedInteractions.add((
      interactionType: interactionType,
      position: position,
      timestamp: timestamp,
    ));
  }

  @override
  void captureTouchMove(List<TouchPosition> positions, DateTime timestamp) {
    capturedTouchMoves.add((positions: positions, timestamp: timestamp));
  }

  @override
  Future<void> captureSnapshot(
    RenderRepaintBoundary boundary, {
    required Element boundaryElement,
  }) async {
    captureSnapshotCallCount++;
    capturedSnapshots.add((
      boundary: boundary,
      boundaryElement: boundaryElement,
    ));
  }
}
