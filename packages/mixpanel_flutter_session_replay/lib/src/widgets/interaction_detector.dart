import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';

import '../internal/widget_coordinator.dart';
import '../internal/settings/settings_service.dart';
import '../models/results.dart';
import '../models/rrweb_types.dart';

/// Internal widget that detects and captures user interactions
class InteractionDetector extends StatelessWidget {
  const InteractionDetector({
    super.key,
    required this.coordinator,
    required this.child,
  });

  final WidgetCoordinator coordinator;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerDown: _handlePointerDown, child: child);
  }

  void _handlePointerDown(PointerDownEvent event) {
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

    // Capture touchStart interaction at local position
    // The coordinator will handle triggering capture internally
    coordinator.captureInteraction(
      RRWebMouseInteraction.touchStart,
      event.localPosition,
    );
  }
}
