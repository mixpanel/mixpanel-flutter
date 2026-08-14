import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/masking_directive.dart';
import '../models/results.dart';
import '../models/session_event.dart' show TouchPosition;
import 'settings/settings_service.dart';
import 'logger.dart';

/// Abstract interface for widget-level coordinator operations
///
/// Defines the contract between widgets (LifecycleObserver, InteractionDetector,
/// FrameMonitor) and the coordinator. Contains only the subset of coordinator
/// functionality that widgets need.
///
/// This enables lightweight widget testing with simple fakes instead of
/// requiring the full [SessionReplayCoordinator] with all its dependencies.
abstract class WidgetCoordinator {
  /// Current recording state
  RecordingState get recordingState;

  /// Remote settings state (pending, enabled, or disabled)
  RemoteEnablementState get remoteEnablementState;

  /// Whether app is currently in foreground
  bool get isAppInForeground;

  /// Logger instance
  MixpanelLogger get logger;

  /// Notifier for debug mask regions (for overlay visualization)
  ValueNotifier<List<MaskRegionInfo>> get maskRegionsNotifier;

  /// Handle app returning to foreground
  void onAppForegrounded();

  /// Handle app going to background
  void onAppBackgrounded();

  /// Capture a gesture boundary (down, lift, or cancel) that happened at
  /// [timestamp]
  void captureInteraction(
    int interactionType,
    Offset position,
    DateTime timestamp,
  );

  /// Capture a batch of sampled drag positions, stamped with the time of its
  /// final position
  void captureTouchMove(List<TouchPosition> positions, DateTime timestamp);

  /// Capture a screenshot from the given boundary
  Future<void> captureSnapshot(RenderRepaintBoundary boundary);
}
