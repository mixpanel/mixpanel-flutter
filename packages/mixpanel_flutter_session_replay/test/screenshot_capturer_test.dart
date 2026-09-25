import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/native_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_manager.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/wireframe/wireframe_emitter.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';

import 'utils/golden_test_utils.dart';

class _UnavailableCompressor extends ImageCompressor {
  @override
  bool get isAvailable => false;

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  }) => throw StateError('compress must not be called');

  @override
  Future<void> dispose() async {}
}

class _RecordingCompressor extends ImageCompressor {
  int? width;
  int? height;
  List<Rect>? maskRects;

  @override
  bool get paintsMasks => true;

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  }) async {
    this.width = width;
    this.height = height;
    this.maskRects = maskRects;
    return Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
  }

  @override
  Future<void> dispose() async {}
}

class _DirectSurfaceCompressor extends ImageCompressor {
  Size? logicalSize;
  int? outputWidth;
  int? outputHeight;
  List<Rect>? maskRects;
  Future<void> Function()? duringPresentation;
  Future<void> Function()? beforeValidation;
  bool invokesSnapshotValidation = true;
  int surfaceCaptureCount = 0;

  @override
  bool get capturesRenderedSurface => true;

  @override
  Future<void> waitForRenderedSurfacePresentation() async {
    await duringPresentation?.call();
  }

  @override
  Future<Uint8List?> captureRenderedSurface({
    required Size logicalSize,
    required int outputWidth,
    required int outputHeight,
    List<Rect> maskRects = const [],
    bool Function()? validateSnapshot,
  }) async {
    surfaceCaptureCount++;
    this.logicalSize = logicalSize;
    this.outputWidth = outputWidth;
    this.outputHeight = outputHeight;
    this.maskRects = maskRects;
    await beforeValidation?.call();
    if (invokesSnapshotValidation &&
        validateSnapshot != null &&
        !validateSnapshot()) {
      return null;
    }
    return Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]);
  }

  @override
  Future<Uint8List?> compress(
    Uint8List rgbaBytes, {
    required int width,
    required int height,
    List<Rect> maskRects = const [],
  }) => throw StateError('RGBA compression must not be called');

  @override
  Future<void> dispose() async {}
}

void main() {
  group('ScreenshotCapturer raster budget', () {
    test('leaves normal phone viewports at logical resolution', () {
      expect(ScreenshotCapturer.capturePixelRatioFor(const Size(375, 812)), 1);
    });

    test('scales 1080p and 4K to the 1280x720 raster budget', () {
      expect(
        ScreenshotCapturer.capturePixelRatioFor(const Size(1920, 1080)),
        closeTo(2 / 3, 0.000001),
      );
      expect(
        ScreenshotCapturer.capturePixelRatioFor(const Size(3840, 2160)),
        closeTo(1 / 3, 0.000001),
      );
    });

    test('uses the available budget for a nearly square desktop viewport', () {
      final ratio = ScreenshotCapturer.capturePixelRatioFor(
        const Size(1200, 1214),
      );

      expect(ratio, closeTo(0.7954, 0.0001));
      expect((1200 * ratio).ceil(), 955);
      expect((1214 * ratio).ceil(), 966);
    });

    test('also caps the longest edge of pathological viewports', () {
      expect(
        ScreenshotCapturer.capturePixelRatioFor(const Size(10000, 200)),
        closeTo(0.192, 0.000001),
      );
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
        compressor: _RecordingCompressor(),
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
          compressor: compressor,
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
        expect(compressor.maskRects, hasLength(success.maskRegions.length));
        final logicalMask = success.maskRegions.first.bounds;
        final rasterMask = compressor.maskRects!.first;
        expect(rasterMask.left, closeTo(logicalMask.left, 0.01));
        expect(rasterMask.top, closeTo(logicalMask.top, 0.01));
        expect(rasterMask.width, closeTo(logicalMask.width, 0.01));
        expect(rasterMask.height, closeTo(logicalMask.height, 0.01));
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
        final compressor = _DirectSurfaceCompressor();
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          compressor: compressor,
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
        final compressor = _DirectSurfaceCompressor()
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
          compressor: compressor,
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
        final compressor = _DirectSurfaceCompressor()
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
          compressor: compressor,
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
      },
    );

    testWidgets(
      'direct surface capture fails closed without post-snapshot validation',
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
        final compressor = _DirectSurfaceCompressor()
          ..invokesSnapshotValidation = false;
        final capturer = ScreenshotCapturer(
          directive: MaskingDirective(
            autoMaskTypes: const {AutoMaskedView.text},
          ),
          logger: MixpanelLogger(LogLevel.none),
          debugOverlayEnabled: false,
          compressor: compressor,
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
        expect(failure.errorMessage, contains('not validated'));
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
          compressor: DartPngCompressor(),
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

    testWidgets('skips frame capture when compression is unavailable', (
      tester,
    ) async {
      final target = await pumpScreen(tester);
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: {}),
        logger: logger,
        debugOverlayEnabled: false,
        compressor: _UnavailableCompressor(),
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
