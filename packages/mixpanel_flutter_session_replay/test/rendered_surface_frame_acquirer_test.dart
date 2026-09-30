import 'dart:typed_data';
import 'dart:ui' show FrameTiming;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/frame_acquirer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/mask_layout_fence.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/raster_completion_barrier.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/rendered_surface_capture.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/rendered_surface_frame_acquirer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';

import 'helpers/raster_test_binding.dart';

void main() {
  RasterTestBinding();
  testWidgets('should not snapshot until the observed frame is rasterized', (
    tester,
  ) async {
    final request = await _request(tester);
    final surface = _Surface();
    final acquirer = RenderedSurfaceFrameAcquirer(
      surface,
      rasterCompletion: RasterCompletionBarrier(),
    );
    addTearDown(acquirer.dispose);
    final pending = acquirer.acquire(request);
    await tester.idle();
    expect(surface.snapshots, 0);

    _acknowledge(tester);
    expect(await pending, isA<AcquiredFrame>());
    expect(surface.snapshots, 1);
  });

  testWidgets('should not snapshot if cancelled while waiting for raster', (
    tester,
  ) async {
    var cancelled = false;
    final request = await _request(tester, isCancelled: () => cancelled);
    final surface = _Surface();
    final acquirer = RenderedSurfaceFrameAcquirer(
      surface,
      rasterCompletion: RasterCompletionBarrier(),
    );
    addTearDown(acquirer.dispose);
    final pending = acquirer.acquire(request);
    cancelled = true;
    _acknowledge(tester);

    final result = await pending as FrameRejected;
    expect(result.failure.error, CaptureError.cancelled);
    expect(surface.snapshots, 0);
  });

  testWidgets('should not snapshot after a raster acknowledgement timeout', (
    tester,
  ) async {
    final request = await _request(tester);
    final surface = _Surface();
    final acquirer = RenderedSurfaceFrameAcquirer(
      surface,
      rasterCompletion: RasterCompletionBarrier(),
    );
    addTearDown(acquirer.dispose);
    final pending = acquirer.acquire(request);
    await tester.binding.delayed(const Duration(milliseconds: 500));

    final result = await pending as FrameRejected;
    expect(result.failure.error, CaptureError.maskDetectionFailed);
    expect(surface.snapshots, 0);
  });

  testWidgets('should reject an in-flight raster wait on acquirer disposal', (
    tester,
  ) async {
    final request = await _request(tester);
    final surface = _Surface();
    final acquirer = RenderedSurfaceFrameAcquirer(
      surface,
      rasterCompletion: RasterCompletionBarrier(),
    );
    final pending = acquirer.acquire(request);
    await acquirer.dispose();

    expect(await pending, isA<FrameRejected>());
    expect(surface.snapshots, 0);
    expect(surface.disposed, isTrue);
  });

  testWidgets('should preserve capture without a raster barrier', (
    tester,
  ) async {
    final request = await _request(tester);
    final surface = _Surface();
    final acquirer = RenderedSurfaceFrameAcquirer(surface);
    addTearDown(acquirer.dispose);

    expect(
      await acquirer.prepare(request.logicalSize),
      FrameSourceStatus.ready,
    );
    expect(await acquirer.acquire(request), isA<AcquiredFrame>());
    expect(surface.snapshots, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

Future<FrameRequest> _request(
  WidgetTester tester, {
  bool Function()? isCancelled,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: const SizedBox()));
  final element = key.currentContext! as Element;
  final boundary = element.findRenderObject()! as RenderRepaintBoundary;
  return FrameRequest(
    boundary: boundary,
    logicalSize: boundary.size,
    maskRegions: const [],
    isCancelled: isCancelled ?? () => false,
    fence: MaskLayoutFence(
      directive: MaskingDirective(autoMaskTypes: const {}),
      trackUnmaskBounds: false,
      boundary: boundary,
      boundaryElement: element,
      observed: MaskDetectionResult(maskRegions: const []),
      observedViewport: boundary.size,
      observedFrameTimeStamp: tester.binding.currentSystemFrameTimeStamp,
    ),
  );
}

void _acknowledge(WidgetTester tester) {
  tester.platformDispatcher.onReportTimings!([
    FrameTiming(
      vsyncStart: 0,
      buildStart: 1,
      buildFinish: 2,
      rasterStart: 3,
      rasterFinish: 4,
      rasterFinishWallTime: 4,
      frameNumber: tester.platformDispatcher.frameData.frameNumber,
    ),
  ]);
}

class _Surface extends RenderedSurfaceCapture {
  int snapshots = 0;
  bool disposed = false;

  @override
  bool get isAvailable => !disposed;

  @override
  Future<CapturedSurface?> capture({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
  }) async {
    snapshots++;
    return _Snapshot();
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class _Snapshot implements CapturedSurface {
  @override
  Future<Uint8List?> encode({required List<Rect> maskRects}) async =>
      Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);

  @override
  void dispose() {}
}
