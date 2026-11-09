import 'package:clock/clock.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../models/masking_directive.dart';
import '../../models/results.dart';
import '../masking/mask_detector.dart';

/// Checks that the masks a capture observed still describe the render tree.
///
/// Acquirers whose pixels are taken after the mask walk (the web surface
/// snapshot lags it by at least one browser presentation) run [check] once the
/// pixels are immutable. Motion anywhere across that interval fails closed.
class MaskLayoutFence {
  static const _tolerance = 0.1;

  final MaskingDirective _directive;
  final bool _trackUnmaskBounds;
  final RenderRepaintBoundary _boundary;
  final Element _boundaryElement;
  final MaskDetectionResult _observed;
  final Size _observedViewport;
  final Duration _observedFrameTimeStamp;

  /// How long the most recent [check] took, or null if it never ran.
  Duration? lastCheckTime;

  MaskLayoutFence({
    required MaskingDirective directive,
    required bool trackUnmaskBounds,
    required RenderRepaintBoundary boundary,
    required Element boundaryElement,
    required MaskDetectionResult observed,
    required Size observedViewport,
    required Duration observedFrameTimeStamp,
  }) : _directive = directive,
       _trackUnmaskBounds = trackUnmaskBounds,
       _boundary = boundary,
       _boundaryElement = boundaryElement,
       _observed = observed,
       _observedViewport = observedViewport,
       _observedFrameTimeStamp = observedFrameTimeStamp;

  /// Returns null when the observed masks still hold, or why they do not.
  CaptureFailure? check() {
    final start = clock.now();
    // A browser presentation does not necessarily produce a new Flutter
    // frame. If Flutter's engine-frame timestamp is unchanged, the pixels can
    // only contain the same rendered geometry the mask walk observed.
    // Avoiding a duplicate walk here is the common static-screen path.
    // Animated, scrolling, or rebuilt screens advance the timestamp and still
    // take the full fail-closed comparison below.
    if (SchedulerBinding.instance.currentSystemFrameTimeStamp ==
        _observedFrameTimeStamp) {
      lastCheckTime = Duration.zero;
      return null;
    }
    MaskDetectionResult current;
    try {
      current = MaskDetector(
        directive: _directive,
        trackUnmaskBounds: _trackUnmaskBounds,
      ).detectMaskRegions(_boundary, boundaryElement: _boundaryElement);
    } catch (error) {
      lastCheckTime = clock.now().difference(start);
      return CaptureFailure(
        CaptureError.maskDetectionFailed,
        'Post-capture mask detection failed: $error',
      );
    }
    lastCheckTime = clock.now().difference(start);

    if (!_layoutMatches(current, _boundary.size)) {
      return const CaptureFailure(
        CaptureError.maskDetectionFailed,
        'Layout changed across presentation or capture - masks no longer valid',
      );
    }
    return null;
  }

  bool _layoutMatches(MaskDetectionResult current, Size currentViewport) {
    bool close(double first, double second) =>
        (first - second).abs() <= _tolerance;

    if (current.shouldSkipCapture ||
        !close(_observedViewport.width, currentViewport.width) ||
        !close(_observedViewport.height, currentViewport.height) ||
        _observed.maskRegions.length != current.maskRegions.length) {
      return false;
    }

    for (var index = 0; index < _observed.maskRegions.length; index++) {
      final first = _observed.maskRegions[index];
      final second = current.maskRegions[index];
      if (first.source != second.source ||
          !close(first.bounds.left, second.bounds.left) ||
          !close(first.bounds.top, second.bounds.top) ||
          !close(first.bounds.right, second.bounds.right) ||
          !close(first.bounds.bottom, second.bounds.bottom)) {
        return false;
      }
    }
    return true;
  }
}
