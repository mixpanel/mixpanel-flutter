import 'package:mixpanel_flutter_session_replay/src/internal/capture/to_image_frame_acquirer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/rendered_surface_frame_acquirer.dart';
import 'dart:typed_data';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/capture/rendered_surface_capture.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_manager.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/wireframe/wireframe_emitter.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';

import 'package:mixpanel_flutter_session_replay/src/widgets/widgets.dart';

import 'utils/golden_test_utils.dart';

class _UnavailableCompressor extends ImageCompressor {
  @override
  bool get isAvailable => false;

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
  }) => throw StateError('compress must not be called');

  @override
  Future<void> dispose() async {}
}

class _RecordingCompressor extends ImageCompressor {
  int? width;
  int? height;
  Uint8List? rgbaBytes;

  /// The RGBA pixel handed to the compressor at raster ([x], [y]).
  List<int> pixelAt(int x, int y) {
    final offset = (y * width! + x) * 4;
    return rgbaBytes!.sublist(offset, offset + 4);
  }

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
  }) async {
    this.width = width;
    this.height = height;
    this.rgbaBytes = Uint8List.fromList(rgbaBytes);
    return Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
  }

  @override
  Future<void> dispose() async {}
}

class _DirectSurfaceCapture extends RenderedSurfaceCapture {
  RenderedSurfaceAvailability availability =
      RenderedSurfaceAvailability.available;
  Size? logicalSize;
  int? outputWidth;
  int? outputHeight;
  List<Rect>? maskRects;
  Future<void> Function()? duringPresentation;
  Future<void> Function()? beforeValidation;
  bool returnsSnapshot = true;
  int surfaceCaptureCount = 0;
  int encodedCount = 0;
  int disposedCount = 0;

  @override
  bool get isAvailable => true;
  @override
  Future<RenderedSurfaceAvailability> waitUntilRenderedSurfaceAvailable(
    Size logicalSize,
  ) async => availability;
  @override
  Future<void> waitForRenderedSurfacePresentation() async {
    await duringPresentation?.call();
  }

  @override
  Future<CapturedSurface?> capture({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
  }) async {
    surfaceCaptureCount++;
    this.logicalSize = logicalSize;
    this.outputWidth = outputWidth;
    this.outputHeight = outputHeight;
    await beforeValidation?.call();
    return returnsSnapshot ? _TestSurface(this) : null;
  }

  @override
  Future<void> dispose() async {}
}

class _TestSurface implements CapturedSurface {
  final _DirectSurfaceCapture source;
  _TestSurface(this.source);
  @override
  Future<Uint8List?> encode({required List<Rect> maskRects}) async {
    source.maskRects = maskRects;
    source.encodedCount++;
    return Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
  }

  @override
  void dispose() => source.disposedCount++;
}

void main() {
  group('ScreenshotCapturer raster budget', () {
    test('leaves normal phone viewports at logical resolution', () {
      expect(
        RenderedSurfaceFrameAcquirer.capturePixelRatioFor(const Size(375, 812)),
        1,
      );
    });

    test('scales 1080p and 4K to the 1280x720 raster budget', () {
      expect(
        RenderedSurfaceFrameAcquirer.capturePixelRatioFor(
          const Size(1920, 1080),
        ),
        closeTo(2 / 3, 0.000001),
      );
      expect(
        RenderedSurfaceFrameAcquirer.capturePixelRatioFor(
          const Size(3840, 2160),
        ),
        closeTo(1 / 3, 0.000001),
      );
    });

    test('uses the available budget for a nearly square desktop viewport', () {
      final ratio = RenderedSurfaceFrameAcquirer.capturePixelRatioFor(
        const Size(1200, 1214),
      );

      expect(ratio, closeTo(0.7954, 0.0001));
      expect((1200 * ratio).ceil(), 955);
      expect((1214 * ratio).ceil(), 966);
    });

    test('also caps the longest edge of pathological viewports', () {
      expect(
        RenderedSurfaceFrameAcquirer.capturePixelRatioFor(
          const Size(10000, 200),
        ),
        closeTo(0.192, 0.000001),
      );
    });

    testWidgets('should cover the whole masked widget when the boundary has a '
        'fractional width', (tester) async {
      // GIVEN a boundary whose logical width is fractional, as on devices
      // with a fractional device pixel ratio, so toImage() rounds the
      // raster up without stretching its content
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 200.5,
                height: 40,
                child: Stack(
                  children: [
                    Positioned(
                      left: 100,
                      top: 0,
                      width: 60,
                      height: 40,
                      child: MixpanelMask(
                        child: ColoredBox(color: Color(0xFFFF0000)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final element = key.currentContext! as Element;
      final boundary = element.findRenderObject()! as RenderRepaintBoundary;
      final compressor = _RecordingCompressor();
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: const {}),
        logger: MixpanelLogger(LogLevel.none),
        debugOverlayEnabled: false,
        frameAcquirer: ToImageFrameAcquirer(
          compressor,
          logger: MixpanelLogger(LogLevel.none),
        ),
      );

      // WHEN the frame is captured
      final pending = tester.runAsync(
        () => capturer.capture(
          boundary,
          boundaryElement: element,
          getCurrentSession: SessionManager().getCurrentSession,
          getDistinctId: () => 'screenshot-capturer-test-distinct-id',
        ),
      );
      await tester.pump();
      final result = await pending;

      // THEN the mask is painted at the widget's own coordinates, so the
      // widget's first and last pixel columns are fully covered
      expect(result, isA<CaptureSuccess>());
      expect(compressor.width, 201);
      expect(compressor.pixelAt(100, 20), [0xcc, 0xcc, 0xcc, 0xff]);
      expect(compressor.pixelAt(159, 20), [0xcc, 0xcc, 0xcc, 0xff]);
    });

    testWidgets('native capture does not re-walk masks after toImage', (
      tester,
    ) async {
      // GIVEN a native (render tree) capture of masked text
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: const ColoredBox(
              color: Colors.white,
              child: Text('Sensitive account details'),
            ),
          ),
        ),
      );
      final element = key.currentContext! as Element;
      final boundary = element.findRenderObject()! as RenderRepaintBoundary;
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: const {AutoMaskedView.text}),
        logger: MixpanelLogger(LogLevel.none),
        debugOverlayEnabled: false,
        frameAcquirer: ToImageFrameAcquirer(
          _RecordingCompressor(),
          logger: MixpanelLogger(LogLevel.none),
        ),
      );

      // WHEN the frame is captured
      final pending = tester.runAsync(
        () => capturer.capture(
          boundary,
          boundaryElement: element,
          getCurrentSession: SessionManager().getCurrentSession,
          getDistinctId: () => 'screenshot-capturer-test-distinct-id',
        ),
      );
      await tester.pump();
      final result = await pending;

      // THEN it succeeds without a post-snapshot validation walk, because
      // toImage() snapshots the same frame the mask walk observed
      expect(result, isA<CaptureSuccess>());
      expect(capturer.lastPostSnapshotMaskValidationTime, isNull);
    });

    testWidgets(
      'should keep a native frame when recording stops after toImage is called',
      (tester) async {
        // GIVEN a settled screen
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: Colors.white,
                child: Text('Screen B'),
              ),
            ),
          ),
        );
        await tester.pump();
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        final compressor = _RecordingCompressor();
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(autoMaskTypes: const {}),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: ToImageFrameAcquirer(
            compressor,
            logger: MixpanelLogger(LogLevel.none),
          ),
        );

        // WHEN recording stops once the mask walk has read the render tree.
        // Nothing yields between that read and toImage(), so this is a stop
        // after the frame was fixed. The capture starts outside the
        // fake-async zone so toImage() can complete, and waits on the frame
        // it requested from the idle scheduler.
        var stopped = false;
        late Future<CaptureResult> pending;
        await tester.runAsync(() async {
          pending = capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
            isCancelled: () => stopped,
            onRenderTreeRead: () => stopped = true,
          );
        });
        await tester.pump();
        final result = await tester.runAsync(() => pending);
        expect(stopped, isTrue, reason: 'sanity: the stop happened');

        // THEN the frame, fixed before the stop, is still encoded for its
        // replay rather than dropped
        expect(result, isA<CaptureSuccess>());
        expect(compressor.width, isNotNull);
      },
    );

    Future<(Element, RenderRepaintBoundary)> pumpSettledScreen(
      WidgetTester tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: const ColoredBox(
              color: Colors.white,
              child: Text('Settled screen'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
      final element = key.currentContext! as Element;
      return (element, element.findRenderObject()! as RenderRepaintBoundary);
    }

    testWidgets('should request a painted frame when the scheduler is idle '
        'without follow-ups', (tester) async {
      // GIVEN a painted, settled screen with no frame in flight, and the
      // native acquirer, which does not follow up frames during a capture
      final (element, boundary) = await pumpSettledScreen(tester);
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: const {}),
        logger: MixpanelLogger(LogLevel.none),
        debugOverlayEnabled: false,
        frameAcquirer: ToImageFrameAcquirer(
          _RecordingCompressor(),
          logger: MixpanelLogger(LogLevel.none),
        ),
      );

      // WHEN a capture starts from an idle scheduler, as a deferred
      // rate-limit capture does. Started outside the fake-async zone so
      // toImage() can complete once the frame is pumped.
      late Future<CaptureResult> pending;
      await tester.runAsync(() async {
        pending = capturer.capture(
          boundary,
          boundaryElement: element,
          getCurrentSession: SessionManager().getCurrentSession,
          getDistinctId: () => 'screenshot-capturer-test-distinct-id',
        );
      });

      // THEN it waits on a frame it requested, as before web support
      expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);
      await tester.pump();
      final result = await tester.runAsync(() => pending);
      expect(result, isA<CaptureSuccess>());
    });

    testWidgets('should not request a frame when the scheduler is idle with '
        'follow-ups', (tester) async {
      // GIVEN a painted, settled screen with no frame in flight, and the web
      // acquirer, which follows up frames during a capture
      final (element, boundary) = await pumpSettledScreen(tester);
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: const {}),
        logger: MixpanelLogger(LogLevel.none),
        debugOverlayEnabled: false,
        frameAcquirer: RenderedSurfaceFrameAcquirer(_DirectSurfaceCapture()),
      );

      // WHEN a capture starts from an idle scheduler
      final pending = tester.runAsync(
        () => capturer.capture(
          boundary,
          boundaryElement: element,
          getCurrentSession: SessionManager().getCurrentSession,
          getDistinctId: () => 'screenshot-capturer-test-distinct-id',
        ),
      );

      // THEN it does not ask Flutter for a frame. That frame would count as
      // one rendered during the capture and owe a follow-up that requests
      // another, forever, on a static screen.
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
      final result = await pending;
      expect(result, isA<CaptureSuccess>());
      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    });

    testWidgets(
      'keeps native raster and mask coordinates at logical resolution',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1920, 1080);
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: Colors.white,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.all(60),
                    child: Text('Sensitive account details'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        final compressor = _RecordingCompressor();
        final logger = MixpanelLogger(LogLevel.none);
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: logger,
          debugOverlayEnabled: false,
          frameAcquirer: ToImageFrameAcquirer(
            compressor,
            logger: MixpanelLogger(LogLevel.none),
          ),
          wireframeEmitter: WireframeEmitter(
            sensitiveRules: const [],
            debugEmitter: null,
            logger: logger,
          ),
        );
        capturer.applyRemoteWireframeVerdict(isEnabled: true);

        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
          ),
        );
        await tester.pump();
        final result = await pending;

        expect(result, isA<CaptureSuccess>());
        final success = result! as CaptureSuccess;
        expect((success.width, success.height), (1920, 1080));
        expect(
          (
            success.wireframes!.viewportWidth,
            success.wireframes!.viewportHeight,
          ),
          (1920, 1080),
        );
        expect((compressor.width, compressor.height), (1920, 1080));
        expect(success.maskRegions, isNotEmpty);
        // The mask is painted at its logical coordinates in the raster.
        final logicalMask = success.maskRegions.first.bounds;
        expect(
          compressor.pixelAt(
            logicalMask.center.dx.round(),
            logicalMask.center.dy.round(),
          ),
          [0xcc, 0xcc, 0xcc, 0xff],
        );
      },
    );

    testWidgets(
      'direct surface capture bypasses toImage and receives scaled masks',
      (tester) async {
        // Given a 1080p repaint boundary containing automatically masked text.
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1920, 1080);
        addTearDown(tester.view.reset);
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: const ColoredBox(
                color: Colors.white,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('Sensitive account details'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        final compressor = _DirectSurfaceCapture();
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(compressor),
        );

        // When capture is requested through the platform surface path.
        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
          ),
        );
        await tester.pump();
        final result = await pending;

        // Then no ui.Image/RGBA path is used and output coordinates are scaled.
        expect(result, isA<CaptureSuccess>());
        final success = result! as CaptureSuccess;
        expect(compressor.logicalSize, const Size(1920, 1080));
        expect((compressor.outputWidth, compressor.outputHeight), (1280, 720));
        // Replay metadata must describe the encoded image, not the viewport.
        expect((success.width, success.height), (1280, 720));
        expect(compressor.maskRects, hasLength(success.maskRegions.length));
        final logicalMask = success.maskRegions.first.bounds;
        final outputMask = compressor.maskRects!.first;
        expect(outputMask.left, closeTo(logicalMask.left * 2 / 3, 0.01));
        expect(outputMask.top, closeTo(logicalMask.top * 2 / 3, 0.01));
        expect(outputMask.width, closeTo(logicalMask.width * 2 / 3, 0.01));
        expect(outputMask.height, closeTo(logicalMask.height * 2 / 3, 0.01));
        expect(capturer.lastPostSnapshotMaskValidationTime, Duration.zero);
      },
    );

    testWidgets(
      'direct surface capture rejects motion across browser presentation',
      (tester) async {
        final key = GlobalKey();
        final transformKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 200,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    key: transformKey,
                    offset: Offset.zero,
                    child: const Text('Sensitive account details'),
                  ),
                ),
              ),
            ),
          ),
        );
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        final movingTransform =
            transformKey.currentContext!.findRenderObject()! as RenderTransform;
        final compressor = _DirectSurfaceCapture()
          ..duringPresentation = () async {
            movingTransform.transform = Matrix4.translationValues(40, 0, 0);
            await tester.pump(const Duration(milliseconds: 16));
          };
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(compressor),
        );

        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
          ),
        );
        await tester.pump();
        final result = await pending;

        expect(result, isA<CaptureFailure>());
        final failure = result! as CaptureFailure;
        expect(failure.error, CaptureError.maskDetectionFailed);
        expect(failure.errorMessage, contains('presentation or capture'));
        // The browser surface is made immutable first, then validation spans
        // the presentation and snapshot interval before any worker processing.
        expect(compressor.surfaceCaptureCount, 1);
        expect(compressor.encodedCount, 0);
        expect(compressor.disposedCount, 1);
      },
    );

    testWidgets(
      'cancels before acquiring pixels when recording stops during the wait',
      (tester) async {
        // GIVEN a frame waiting for the browser to present when the replay
        // stops, for example right before a sensitive screen is shown
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 400,
                height: 200,
                child: Text('Account balance'),
              ),
            ),
          ),
        );
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        var stopped = false;
        final compressor = _DirectSurfaceCapture()
          ..duringPresentation = () async {
            stopped = true;
          };
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(compressor),
        );

        // WHEN
        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
            isCancelled: () => stopped,
          ),
        );
        await tester.pump();
        final result = await pending;

        // THEN no pixels were read from the surface at all
        expect(result, isA<CaptureFailure>());
        expect((result! as CaptureFailure).error, CaptureError.cancelled);
        expect(compressor.surfaceCaptureCount, 0);
        expect(compressor.encodedCount, 0);
      },
    );

    testWidgets(
      'releases an acquired snapshot without encoding when cancelled',
      (tester) async {
        // GIVEN the replay stops after the immutable snapshot was taken but
        // before it was encoded
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 400,
                height: 200,
                child: Text('Account balance'),
              ),
            ),
          ),
        );
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        var stopped = false;
        final compressor = _DirectSurfaceCapture()
          ..beforeValidation = () async {
            stopped = true;
          };
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(compressor),
        );

        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
            isCancelled: () => stopped,
          ),
        );
        await tester.pump();
        final result = await pending;

        // THEN the snapshot is disposed, never encoded
        expect((result! as CaptureFailure).error, CaptureError.cancelled);
        expect(compressor.surfaceCaptureCount, 1);
        expect(compressor.encodedCount, 0);
        expect(compressor.disposedCount, 1);
      },
    );

    testWidgets(
      'direct surface capture rejects a mask that moves before validation',
      (tester) async {
        final key = GlobalKey();
        final transformKey = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 200,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Transform.translate(
                    key: transformKey,
                    offset: Offset.zero,
                    child: const Text('Sensitive account details'),
                  ),
                ),
              ),
            ),
          ),
        );
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        final movingTransform =
            transformKey.currentContext!.findRenderObject()! as RenderTransform;
        final compressor = _DirectSurfaceCapture()
          ..beforeValidation = () async {
            // Simulate a paint transform changing while asynchronous snapshot
            // creation is in flight. localToGlobal observes this immediately.
            movingTransform.transform = Matrix4.translationValues(180, 0, 0);
            await tester.pump(const Duration(milliseconds: 16));
          };
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(compressor),
        );

        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
          ),
        );
        await tester.pump();
        final result = await pending;

        expect(result, isA<CaptureFailure>());
        final failure = result! as CaptureFailure;
        expect(failure.error, CaptureError.maskDetectionFailed);
        expect(failure.errorMessage, contains('masks no longer valid'));
        expect(compressor.encodedCount, 0);
        expect(compressor.disposedCount, 1);
      },
    );

    testWidgets(
      'direct surface capture fails closed when acquisition returns no snapshot',
      (tester) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: const Text('Sensitive account details'),
            ),
          ),
        );
        final element = key.currentContext! as Element;
        final boundary = element.findRenderObject()! as RenderRepaintBoundary;
        final compressor = _DirectSurfaceCapture()..returnsSnapshot = false;
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(compressor),
        );

        final pending = tester.runAsync(
          () => capturer.capture(
            boundary,
            boundaryElement: element,
            getCurrentSession: SessionManager().getCurrentSession,
            getDistinctId: () => 'screenshot-capturer-test-distinct-id',
          ),
        );
        await tester.pump();
        final result = await pending;

        expect(result, isA<CaptureFailure>());
        final failure = result! as CaptureFailure;
        expect(failure.error, CaptureError.renderBoundaryNotFound);
        expect(compressor.encodedCount, 0);
      },
    );
  });

  group('ScreenshotCapturer wireframe kill switch', () {
    final logger = MixpanelLogger(LogLevel.none);

    ScreenshotCapturer createCapturer({required bool withEmitter}) =>
        ScreenshotCapturer(
          directive: MaskingDirective(autoMaskTypes: {}),
          logger: logger,
          debugOverlayEnabled: false,
          frameAcquirer: ToImageFrameAcquirer(
            DartPngCompressor(),
            logger: MixpanelLogger(LogLevel.none),
          ),
          wireframeEmitter: withEmitter
              ? WireframeEmitter(
                  sensitiveRules: const [],
                  debugEmitter: null,
                  logger: logger,
                )
              : null,
        );

    /// Pumps a one-screen tree and returns its repaint boundary.
    Future<({RenderRepaintBoundary boundary, Element element})> pumpScreen(
      WidgetTester tester,
    ) async {
      await loadTestFont();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: ValueKey('capture-boundary'),
                child: SizedBox(
                  width: 300,
                  height: 200,
                  child: Center(child: Text('Sign in')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return (
        boundary: tester.allRenderObjects
            .whereType<RenderRepaintBoundary>()
            .first,
        element: tester.element(find.byKey(const ValueKey('capture-boundary'))),
      );
    }

    /// Runs one real capture. Mirrors `captureGolden`: the capture has to run
    /// outside the fake-async zone so its `endOfFrame` resolves against a
    /// pumped frame.
    Future<CaptureSuccess> capture(
      WidgetTester tester,
      ScreenshotCapturer capturer,
      ({RenderRepaintBoundary boundary, Element element}) target,
    ) async {
      final pending = tester.runAsync(
        () => capturer.capture(
          target.boundary,
          boundaryElement: target.element,
          getCurrentSession: SessionManager().getCurrentSession,
          getDistinctId: () => 'screenshot-capturer-test-distinct-id',
        ),
      );
      await tester.pump();
      final result = await pending;
      expect(result, isA<CaptureSuccess>());
      return result! as CaptureSuccess;
    }

    testWidgets('emits nothing until the server verdict arrives', (
      tester,
    ) async {
      // GIVEN - wireframes opted in locally, `/settings` has not answered yet.
      // A manually started recording can capture in this window, so the
      // payload must stay off until the server has been asked.
      final boundary = await pumpScreen(tester);
      final capturer = createCapturer(withEmitter: true);

      // WHEN
      final result = await capture(tester, capturer, boundary);

      // THEN
      expect(capturer.wireframesEnabled, false);
      expect(result.wireframes, isNull);
      expect(result.data, isNotEmpty);
    });

    testWidgets('emits a payload once the server allows wireframes', (
      tester,
    ) async {
      // GIVEN
      final boundary = await pumpScreen(tester);
      final capturer = createCapturer(withEmitter: true);
      capturer.applyRemoteWireframeVerdict(isEnabled: true);

      // WHEN
      final result = await capture(tester, capturer, boundary);

      // THEN
      expect(capturer.wireframesEnabled, true);
      expect(result.wireframes, isNotNull);
      expect(result.wireframes!.elements, isNotEmpty);
    });

    testWidgets('drops the payload once the kill switch fires', (tester) async {
      // GIVEN - same screen, an emitter that was killed remotely
      final boundary = await pumpScreen(tester);
      final capturer = createCapturer(withEmitter: true);
      capturer.applyRemoteWireframeVerdict(isEnabled: false);

      // WHEN
      final result = await capture(tester, capturer, boundary);

      // THEN - the screenshot still lands, the wireframe does not
      expect(capturer.wireframesEnabled, false);
      expect(result.wireframes, isNull);
      expect(result.data, isNotEmpty);
    });

    testWidgets('is a no-op when wireframes were never on', (tester) async {
      // GIVEN
      final boundary = await pumpScreen(tester);
      final capturer = createCapturer(withEmitter: false);

      // WHEN - even an allowing verdict cannot turn on what was never wired
      capturer.applyRemoteWireframeVerdict(isEnabled: true);
      final result = await capture(tester, capturer, boundary);

      // THEN
      expect(capturer.wireframesEnabled, false);
      expect(result.wireframes, isNull);
    });

    testWidgets(
      'reports a missing surface separately from compression failure',
      (tester) async {
        // GIVEN working encoding but no rendered surface to capture
        final target = await pumpScreen(tester);
        final surface = _DirectSurfaceCapture()
          ..availability = RenderedSurfaceAvailability.unavailable;
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(autoMaskTypes: {}),
          logger: logger,
          debugOverlayEnabled: false,
          frameAcquirer: RenderedSurfaceFrameAcquirer(surface),
        );

        // WHEN surface preparation fails
        final result = await capturer.capture(
          target.boundary,
          boundaryElement: target.element,
          getCurrentSession: SessionManager().getCurrentSession,
          getDistinctId: () => 'test-user',
        );

        // THEN it reports the missing surface without attempting encoding
        expect(result, isA<CaptureFailure>());
        expect(
          (result as CaptureFailure).error,
          CaptureError.renderBoundaryNotFound,
        );
        expect(surface.surfaceCaptureCount, 0);
        expect(surface.encodedCount, 0);
      },
    );

    testWidgets('skips frame capture when compression is unavailable', (
      tester,
    ) async {
      final target = await pumpScreen(tester);
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: {}),
        logger: logger,
        debugOverlayEnabled: false,
        frameAcquirer: ToImageFrameAcquirer(
          _UnavailableCompressor(),
          logger: MixpanelLogger(LogLevel.none),
        ),
      );

      final result = await capturer.capture(
        target.boundary,
        boundaryElement: target.element,
        getCurrentSession: SessionManager().getCurrentSession,
        getDistinctId: () => 'screenshot-capturer-test-distinct-id',
      );

      expect(result, isA<CaptureFailure>());
      expect((result as CaptureFailure).error, CaptureError.compressionFailed);
    });
  });
}
