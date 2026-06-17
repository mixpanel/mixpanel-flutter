import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import '../session_replay.dart';
import 'interaction_detector.dart';
import 'frame_monitor.dart';
import 'lifecycle_observer.dart';

/// Wrap your app with this widget to enable Mixpanel Session Replay
///
/// Place this at the root of your widget tree (ex: wrapping MaterialApp or CupertinoApp).
///
/// The [instance] parameter can be null initially and updated later when
/// initialization completes. This allows the app to launch immediately without
/// waiting for async initialization.
class MixpanelSessionReplayWidget extends StatefulWidget {
  const MixpanelSessionReplayWidget({
    super.key,
    required this.instance,
    required this.child,
  });

  /// The MixpanelSessionReplay instance. Can be null if not yet initialized.
  final MixpanelSessionReplay? instance;

  /// The widget tree to enable session replay for
  final Widget child;

  @override
  State<MixpanelSessionReplayWidget> createState() =>
      _MixpanelSessionReplayWidgetState();
}

/// Simple notifier for frame callbacks
class _FrameNotifier extends ChangeNotifier {
  void notify() {
    notifyListeners();
  }
}

class _MixpanelSessionReplayWidgetState
    extends State<MixpanelSessionReplayWidget> {
  // Notifier for frame changes - registered once at widget creation
  // Note: Persistent frame callback cannot be removed, so we register it once
  // at the app root level and notify children when frames occur
  final _FrameNotifier _frameNotifier = _FrameNotifier();

  @override
  void initState() {
    super.initState();
    // Register persistent frame callback once for entire app lifetime
    // This cannot be removed, but since this widget lives at the root,
    // it only gets registered once and persists appropriately
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  void _onFrame(Duration timestamp) {
    if (!mounted) return;
    // Notify all listeners (FrameMonitor) that a frame occurred
    _frameNotifier.notify();
  }

  @override
  void dispose() {
    _frameNotifier.dispose();
    // Note: Persistent frame callback cannot be removed and will continue
    // to fire, but since this widget is disposed, _onFrame returns early
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instance = widget.instance;

    // If instance is null, just return the child without any monitoring
    if (instance == null) {
      return widget.child;
    }

    final coordinator = instance.coordinator;

    // Use ObjectKey to force recreation of child widgets when coordinator changes
    // This ensures all state is fresh and no stale references exist
    return LifecycleObserver(
      key: ObjectKey(coordinator),
      coordinator: coordinator,
      child: InteractionDetector(
        key: ObjectKey(coordinator),
        coordinator: coordinator,
        child: FrameMonitor(
          key: ObjectKey(coordinator),
          frameNotifier: _frameNotifier,
          coordinator: coordinator,
          debugOptions: instance.debugOptions,
          child: widget.child,
        ),
      ),
    );
  }
}
