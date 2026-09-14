@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_image_compressor.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_image_worker.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/remote_enablement_state.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/indexed_db_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/upload_service.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/rrweb_types.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:web/web.dart' as web;

const _uploadServer = 'http://127.0.0.1:8765';
const _benchmarkIterations = 3;
final _benchmarkCapturePixelRatioLimit = double.parse(
  const String.fromEnvironment(
    'WEB_BENCHMARK_CAPTURE_PIXEL_RATIO_LIMIT',
    defaultValue: '1',
  ),
);
const _longFrameThresholdMs = 50.0;
const _allowedAddedFrameDelayMs = int.fromEnvironment(
  'WEB_PERFORMANCE_ALLOWED_ADDED_FRAME_DELAY_MS',
  defaultValue: 24,
);
const _enforcePerformanceBudget = bool.fromEnvironment(
  'ENFORCE_WEB_PERFORMANCE_BUDGET',
  defaultValue: true,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'real browser capture, IndexedDB, gzip, and HTTP upload pipeline',
    (tester) async {
      final queue = IndexedDbEventQueue(
        token: 'web-pipeline-validation',
        logger: MixpanelLogger(LogLevel.none),
      );
      await queue.initialize();
      await queue.removeAll();
      addTearDown(queue.dispose);

      final compressor = WebImageCompressor(
        logger: MixpanelLogger(LogLevel.none),
      );
      await compressor.initialize();
      addTearDown(compressor.dispose);
      final capturer = ScreenshotCapturer(
        directive: MaskingDirective(autoMaskTypes: const {AutoMaskedView.text}),
        logger: MixpanelLogger(LogLevel.none),
        debugOverlayEnabled: false,
        compressor: compressor,
      );

      final boundary = await _pumpScene(tester, complexity: 48);
      await _waitForBrowserFrames(2);
      final capture = await _captureWhenSurfaceReady(
        tester,
        capturer,
        boundary,
      );
      expect(capture, isA<CaptureSuccess>());
      final success = capture as CaptureSuccess;
      expect(success.data, isNotEmpty);
      expect(success.data.take(2), <int>[0xff, 0xd8]);
      expect(success.data.skip(success.data.length - 2), <int>[0xff, 0xd9]);
      _expectEveryMaskIsPainted(success, boundary.boundary.size);

      final session = Session(
        id: 'web-pipeline-session',
        startTime: success.timestamp.subtract(const Duration(seconds: 1)),
        status: SessionStatus.active,
      );
      await queue.createSessionMetadata(session);
      await queue.add(
        SessionReplayEvent(
          sessionId: session.id,
          distinctId: 'web-validation-user',
          timestamp: success.timestamp.subtract(
            const Duration(milliseconds: 1),
          ),
          type: EventType.metadata,
          payload: MetadataPayload(
            width: success.width,
            height: success.height,
          ),
        ),
      );
      await queue.add(
        SessionReplayEvent(
          sessionId: session.id,
          distinctId: 'web-validation-user',
          timestamp: success.timestamp,
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: success.data),
        ),
      );

      final client = http.Client();
      addTearDown(client.close);
      final uploader = UploadService(
        eventQueue: queue,
        payloadSerializer: PayloadSerializer('web-validation-token'),
        wifiOnly: false,
        getRemoteEnablementState: () => RemoteEnablementState.enabled,
        flushInterval: Duration.zero,
        logger: MixpanelLogger(LogLevel.none),
        httpClient: client,
        serverUrl: _uploadServer,
      );
      addTearDown(uploader.dispose);

      await uploader.flush();

      expect(await queue.fetchOldestHeader(), isNull);
    },
  );

  testWidgets(
    'failed upload survives a queue restart and succeeds after reconnect',
    (tester) async {
      const token = 'web-recovery-validation';
      const sessionId = 'web-recovery-session';
      final logger = MixpanelLogger(LogLevel.none);
      final firstQueue = IndexedDbEventQueue(token: token, logger: logger);
      await firstQueue.initialize();
      await firstQueue.removeAll();
      await firstQueue.createSessionMetadata(
        Session(
          id: sessionId,
          startTime: DateTime.now().toUtc(),
          status: SessionStatus.active,
        ),
      );
      await firstQueue.add(
        SessionReplayEvent(
          sessionId: sessionId,
          distinctId: 'web-recovery-user',
          timestamp: DateTime.now().toUtc(),
          type: EventType.interaction,
          payload: InteractionPayload(
            interactionType: RRWebMouseInteraction.click,
            x: 40,
            y: 80,
          ),
        ),
      );

      final failingClient = http.Client();
      final firstUploader = UploadService(
        eventQueue: firstQueue,
        payloadSerializer: PayloadSerializer('web-validation-token'),
        wifiOnly: false,
        getRemoteEnablementState: () => RemoteEnablementState.enabled,
        flushInterval: Duration.zero,
        logger: logger,
        httpClient: failingClient,
        serverUrl: '$_uploadServer/recoverable',
      );
      await firstUploader.flush();
      expect(await firstQueue.fetchOldestHeader(), isNotNull);
      firstUploader.dispose();
      failingClient.close();
      await firstQueue.dispose();

      // Closing and reopening the actual IndexedDB connection models the
      // storage boundary crossed by a reload or an abruptly closed tab.
      final reopenedQueue = IndexedDbEventQueue(token: token, logger: logger);
      await reopenedQueue.initialize();
      addTearDown(reopenedQueue.dispose);
      expect(await reopenedQueue.fetchOldestHeader(), isNotNull);

      final recoveredClient = http.Client();
      addTearDown(recoveredClient.close);
      final recoveredUploader = UploadService(
        eventQueue: reopenedQueue,
        payloadSerializer: PayloadSerializer('web-validation-token'),
        wifiOnly: false,
        getRemoteEnablementState: () => RemoteEnablementState.enabled,
        flushInterval: Duration.zero,
        logger: logger,
        httpClient: recoveredClient,
        serverUrl: '$_uploadServer/recoverable',
      );
      addTearDown(recoveredUploader.dispose);

      await recoveredUploader.flush();

      expect(await reopenedQueue.fetchOldestHeader(), isNull);
      expect(await reopenedQueue.getLastSequenceNumber(sessionId), 0);
    },
  );

  testWidgets('animated scrolling control runs without replay capture', (
    tester,
  ) async {
    final sceneKey = GlobalKey<_MotionMaskSceneState>();
    await tester.pumpWidget(MaterialApp(home: _MotionMaskScene(key: sceneKey)));
    await tester.pumpAndSettle();
    await _waitForBrowserFrames(2);

    final monitor = _RafMonitor()..start();
    final longTaskMonitor = _LongTaskMonitor()..start();
    sceneKey.currentState!.startMotion();
    await Future<void>.delayed(const Duration(seconds: 4));
    sceneKey.currentState!.stopMotion();
    final metrics = monitor.stop(longTasks: longTaskMonitor.stop());

    await _postArtifact(
      'animated_no_capture.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(metrics.toJson())),
      'application/json',
    );
    debugPrint('WEB_ANIMATED_NO_CAPTURE ${jsonEncode(metrics.toJson())}');
  });

  testWidgets('masks real pixels during simultaneous animation and scrolling', (
    tester,
  ) async {
    final compressor = WebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
    );
    await compressor.initialize();
    addTearDown(compressor.dispose);
    final capturer = ScreenshotCapturer(
      directive: MaskingDirective(autoMaskTypes: const {}),
      logger: MixpanelLogger(LogLevel.none),
      debugOverlayEnabled: true,
      compressor: compressor,
    );

    final boundaryKey = GlobalKey();
    final sceneKey = GlobalKey<_MotionMaskSceneState>();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: _MotionMaskScene(key: sceneKey),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _waitForBrowserFrames(2);

    final element = boundaryKey.currentContext! as Element;
    final boundary = element.findRenderObject()! as RenderRepaintBoundary;
    final handle = _BoundaryHandle(boundary: boundary, element: element);
    final scene = sceneKey.currentState!;
    scene.startMotion();

    final liveSamples = <Map<String, Object?>>[];
    var rejectedForMotion = 0;
    for (var attempt = 0; attempt < 16; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 70));
      final scrollOffset = scene.scrollOffset;
      final animationValue = scene.animationValue;
      final result = await _capture(tester, capturer, handle);
      if (result is! CaptureSuccess) {
        rejectedForMotion++;
        continue;
      }

      liveSamples.add(
        await _exportMotionSample(
          name: 'live_${liveSamples.length.toString().padLeft(2, '0')}',
          capture: result,
          logicalSize: boundary.size,
          scrollOffset: scrollOffset,
          animationValue: animationValue,
        ),
      );
    }
    scene.stopMotion();

    // Active movement is allowed to yield an occasional frame only if the
    // geometry is identical across the presentation barrier. Most attempts on
    // a continuously scrolling scene should fail closed.
    expect(
      rejectedForMotion,
      greaterThan(0),
      reason: 'continuous motion was never recognized as unstable',
    );

    final settledSamples = <Map<String, Object?>>[];
    for (var index = 0; index < 6; index++) {
      final fraction = (index + 0.5) / 7;
      scene.setPosition(animationValue: fraction, scrollFraction: fraction);
      await tester.pump();
      await _waitForBrowserFrames(2);
      final result = await _captureWhenSurfaceReady(tester, capturer, handle);
      expect(result, isA<CaptureSuccess>());
      settledSamples.add(
        await _exportMotionSample(
          name: 'settled_${index.toString().padLeft(2, '0')}',
          capture: result as CaptureSuccess,
          logicalSize: boundary.size,
          scrollOffset: scene.scrollOffset,
          animationValue: scene.animationValue,
        ),
      );
    }

    final manifest = <String, Object?>{
      'description':
          'Exact returned replay JPEGs plus the same images with detected mask '
          'coordinates outlined in green. The magenta SECRET pixels exist only '
          'inside moving/scrolling MixpanelMask widgets and must never survive.',
      'live_motion_attempts': 16,
      'live_motion_rejected': rejectedForMotion,
      'live_motion_accepted': liveSamples,
      'settled_visual_samples': settledSamples,
    };
    await _postArtifact(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
      'application/json',
    );
    debugPrint('WEB_MOTION_MASK_VALIDATION ${jsonEncode(manifest)}');
  });

  testWidgets('capture keeps browser frame delivery within budget', (
    tester,
  ) async {
    final compressor = _BenchmarkWebImageCompressor(
      logger: MixpanelLogger(LogLevel.none),
      capturePixelRatioLimit: _benchmarkCapturePixelRatioLimit,
    );
    await compressor.initialize();
    addTearDown(compressor.dispose);
    final capturer = ScreenshotCapturer(
      directive: MaskingDirective(
        autoMaskTypes: const {AutoMaskedView.text, AutoMaskedView.image},
      ),
      logger: MixpanelLogger(LogLevel.none),
      debugOverlayEnabled: false,
      compressor: compressor,
    );

    final results = <String, Object?>{
      'browser': web.window.navigator.userAgent,
      'logical_viewport':
          '${tester.view.physicalSize.width / tester.view.devicePixelRatio}x'
          '${tester.view.physicalSize.height / tester.view.devicePixelRatio}',
      'physical_viewport':
          '${tester.view.physicalSize.width}x${tester.view.physicalSize.height}',
      'device_pixel_ratio': tester.view.devicePixelRatio,
      'capture_pixel_ratio_limit': _benchmarkCapturePixelRatioLimit,
    };
    for (final scenario in <({String name, int complexity})>[
      (name: 'actual_viewport_sparse_72', complexity: 72),
      (name: 'actual_viewport_dense_240', complexity: 240),
    ]) {
      final boundary = await _pumpScene(
        tester,
        complexity: scenario.complexity,
      );
      final baseline = await _measureBaseline();
      final control = await _measureControl(
        baselineMaxGapMs: baseline.maxGapMs,
      );
      results['${scenario.name}_no_sdk_control'] = control.toJson();
      debugPrint(
        'WEB_PERF ${jsonEncode({'${scenario.name}_no_sdk_control': control.toJson()})}',
      );
      final metrics = await _measureCaptures(
        tester,
        capturer,
        compressor,
        boundary,
        baselineMaxGapMs: math.max(baseline.maxGapMs, control.maxGapMs),
      );
      results[scenario.name] = metrics.toJson();
      binding.reportData = results;
      debugPrint('WEB_PERF ${jsonEncode({scenario.name: metrics.toJson()})}');

      if (_enforcePerformanceBudget) {
        expect(
          metrics.addedMaxGapMs,
          lessThanOrEqualTo(_allowedAddedFrameDelayMs),
          reason:
              '${scenario.name} added ${metrics.addedMaxGapMs.toStringAsFixed(1)}ms '
              'of main-thread frame delay',
        );
        expect(
          metrics.maxGapMs,
          lessThanOrEqualTo(
            math.max(
              _longFrameThresholdMs,
              baseline.maxGapMs + _allowedAddedFrameDelayMs,
            ),
          ),
          reason: '${scenario.name} produced a long browser frame gap',
        );
        expect(
          metrics.longFrameCount,
          0,
          reason: '${scenario.name} produced a browser frame gap over 50ms',
        );
        if (metrics.longTaskSupported) {
          expect(
            metrics.longTaskCount,
            0,
            reason: '${scenario.name} produced a main-thread long task',
          );
        }
      }
    }
    final workerBaseline = await _measureBaseline();
    results['worker_only'] = (await _measureWorkerOnly(
      sourceWidth: tester.view.physicalSize.width.round(),
      sourceHeight: tester.view.physicalSize.height.round(),
      outputWidth:
          (tester.view.physicalSize.width /
                  tester.view.devicePixelRatio *
                  _benchmarkCapturePixelRatioLimit)
              .ceil(),
      outputHeight:
          (tester.view.physicalSize.height /
                  tester.view.devicePixelRatio *
                  _benchmarkCapturePixelRatioLimit)
              .ceil(),
      baselineMaxGapMs: workerBaseline.maxGapMs,
    )).toJson();
    await _postArtifact(
      'performance.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(results)),
      'application/json',
    );
  });
}

class _BenchmarkWebImageCompressor extends WebImageCompressor {
  _BenchmarkWebImageCompressor({
    required super.logger,
    required this.capturePixelRatioLimit,
  });

  final double capturePixelRatioLimit;

  @override
  double get maximumCapturePixelRatio => capturePixelRatioLimit;
}

Future<_BoundaryHandle> _pumpScene(
  WidgetTester tester, {
  required int complexity,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: _BenchmarkScene(complexity: complexity),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final element = key.currentContext! as Element;
  return _BoundaryHandle(
    boundary: element.findRenderObject()! as RenderRepaintBoundary,
    element: element,
  );
}

Future<CaptureResult> _capture(
  WidgetTester tester,
  ScreenshotCapturer capturer,
  _BoundaryHandle handle,
) => capturer.capture(handle.boundary, boundaryElement: handle.element);

Future<CaptureResult> _captureWhenSurfaceReady(
  WidgetTester tester,
  ScreenshotCapturer capturer,
  _BoundaryHandle handle,
) async {
  CaptureResult? result;
  for (var attempt = 0; attempt < 3; attempt++) {
    result = await _capture(tester, capturer, handle);
    if (result is CaptureSuccess) return result;
    await _waitForBrowserFrames(1);
  }
  return result!;
}

Future<_FrameMetrics> _measureBaseline() async {
  final monitor = _RafMonitor()..start();
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return monitor.stop();
}

Future<void> _waitForBrowserFrames(int count) async {
  for (var index = 0; index < count; index++) {
    final completer = Completer<void>();
    void onFrame(num _) => completer.complete();
    web.window.requestAnimationFrame(onFrame.toJS);
    await completer.future;
  }
}

Future<_FrameMetrics> _measureControl({
  required double baselineMaxGapMs,
}) async {
  final monitor = _RafMonitor()..start();
  final longTaskMonitor = _LongTaskMonitor()..start();
  await Future<void>.delayed(const Duration(milliseconds: 100));
  for (var i = 0; i < _benchmarkIterations; i++) {
    // Match capture spacing while deliberately omitting session replay work.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final longTasks = longTaskMonitor.stop();
  return monitor.stop(baselineMaxGapMs: baselineMaxGapMs, longTasks: longTasks);
}

Future<_FrameMetrics> _measureWorkerOnly({
  required int sourceWidth,
  required int sourceHeight,
  required int outputWidth,
  required int outputHeight,
  required double baselineMaxGapMs,
}) async {
  final worker = WebImageWorker.create();
  expect(worker, isNotNull);
  final source = web.HTMLCanvasElement()
    ..width = sourceWidth
    ..height = sourceHeight;
  source.context2D
    ..fillStyle = '#7551c2'.toJS
    ..fillRect(0, 0, sourceWidth, sourceHeight);
  final monitor = _RafMonitor()..start();
  final longTaskMonitor = _LongTaskMonitor()..start();
  final processingTimes = <int>[];
  await Future<void>.delayed(const Duration(milliseconds: 100));
  for (var index = 0; index < _benchmarkIterations; index++) {
    final bitmap = await web.window
        .createImageBitmap(
          source,
          web.ImageBitmapOptions(
            resizeWidth: outputWidth,
            resizeHeight: outputHeight,
            resizeQuality: 'high',
          ),
        )
        .toDart;
    final stopwatch = Stopwatch()..start();
    await worker!.processImageBitmap(
      imageBitmap: bitmap,
      width: outputWidth,
      height: outputHeight,
      jpegQuality: 0.8,
      maskRects: const [],
    );
    stopwatch.stop();
    processingTimes.add(stopwatch.elapsedMilliseconds);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  worker!.dispose();
  final longTasks = longTaskMonitor.stop();
  return monitor.stop(
    captureTimesMs: processingTimes,
    baselineMaxGapMs: baselineMaxGapMs,
    longTasks: longTasks,
  );
}

Future<_FrameMetrics> _measureCaptures(
  WidgetTester tester,
  ScreenshotCapturer capturer,
  WebImageCompressor compressor,
  _BoundaryHandle boundary, {
  required double baselineMaxGapMs,
}) async {
  final monitor = _RafMonitor()..start();
  final longTaskMonitor = _LongTaskMonitor()..start();
  final captureTimes = <int>[];
  final capturePhases = <Map<String, int>>[];
  await Future<void>.delayed(const Duration(milliseconds: 100));
  for (var i = 0; i < _benchmarkIterations; i++) {
    final stopwatch = Stopwatch()..start();
    final result = await _capture(tester, capturer, boundary);
    stopwatch.stop();
    expect(result, isA<CaptureSuccess>());
    captureTimes.add(stopwatch.elapsedMilliseconds);
    capturePhases.add({
      'mask_detection_ms': capturer.lastMaskDetectionTime?.inMilliseconds ?? -1,
      'presentation_barrier_ms':
          capturer.lastRenderedSurfaceStabilityValidationTime?.inMilliseconds ??
          -1,
      'post_snapshot_validation_ms':
          capturer.lastPostSnapshotMaskValidationTime?.inMilliseconds ?? -1,
      ...?compressor.lastCaptureTimings?.toMillisecondsJson(),
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(milliseconds: 100));
  final longTasks = longTaskMonitor.stop();
  return monitor.stop(
    captureTimesMs: captureTimes,
    capturePhases: capturePhases,
    baselineMaxGapMs: baselineMaxGapMs,
    longTasks: longTasks,
  );
}

void _expectEveryMaskIsPainted(CaptureSuccess capture, Size logicalSize) {
  final image = img.decodeJpg(capture.data)!;
  final scaleX = image.width / logicalSize.width;
  final scaleY = image.height / logicalSize.height;
  final masks = capture.maskRegions.where(
    (region) => region.source != MaskSource.unmask,
  );
  expect(masks, isNotEmpty);
  for (final mask in masks) {
    final point = mask.bounds.center;
    final x = (point.dx * scaleX).floor().clamp(0, image.width - 1);
    final y = (point.dy * scaleY).floor().clamp(0, image.height - 1);
    final pixel = image.getPixel(x, y);
    expect(pixel.r, closeTo(204, 24), reason: 'unmasked pixel at $point');
    expect(pixel.g, closeTo(204, 24), reason: 'unmasked pixel at $point');
    expect(pixel.b, closeTo(204, 24), reason: 'unmasked pixel at $point');
  }
}

int _countSensitiveChroma(img.Image image) {
  var leakedPixels = 0;
  for (final pixel in image) {
    // The test scene reserves saturated magenta exclusively for pixels inside
    // MixpanelMask. This validates the actual encoded snapshot independently
    // of the mask coordinates reported by Flutter.
    if (pixel.r > 170 && pixel.b > 170 && pixel.g < 110) leakedPixels++;
  }
  return leakedPixels;
}

img.Image _drawMaskCoordinateOverlay(
  img.Image image,
  List<MaskRegionInfo> maskRegions,
  Size logicalSize,
) {
  final annotated = img.Image.from(image);
  final scaleX = image.width / logicalSize.width;
  final scaleY = image.height / logicalSize.height;
  for (final region in maskRegions.where(
    (region) => region.source != MaskSource.unmask,
  )) {
    final rect = region.bounds;
    img.drawRect(
      annotated,
      x1: (rect.left * scaleX).round().clamp(0, image.width - 1),
      y1: (rect.top * scaleY).round().clamp(0, image.height - 1),
      x2: (rect.right * scaleX).round().clamp(0, image.width - 1),
      y2: (rect.bottom * scaleY).round().clamp(0, image.height - 1),
      color: img.ColorRgb8(0, 255, 64),
      thickness: 3,
    );
  }
  return annotated;
}

Future<void> _postArtifact(
  String name,
  List<int> bytes,
  String contentType,
) async {
  final response = await http.post(
    Uri.parse('$_uploadServer/artifact/$name'),
    headers: {'Content-Type': contentType},
    body: bytes,
  );
  expect(response.statusCode, 200);
}

Future<Map<String, Object?>> _exportMotionSample({
  required String name,
  required CaptureSuccess capture,
  required Size logicalSize,
  required double scrollOffset,
  required double animationValue,
}) async {
  final decoded = img.decodeJpg(capture.data)!;
  final overlay = _drawMaskCoordinateOverlay(
    decoded,
    capture.maskRegions,
    logicalSize,
  );
  await _postArtifact('$name.jpg', capture.data, 'image/jpeg');
  await _postArtifact(
    '${name}_overlay.png',
    img.encodePng(overlay),
    'image/png',
  );
  final leakedPixels = _countSensitiveChroma(decoded);
  debugPrint(
    'WEB_MOTION_SAMPLE name=$name scroll=$scrollOffset '
    'animation=$animationValue masks=${capture.maskCount} '
    'leaked_pixels=$leakedPixels',
  );
  expect(
    leakedPixels,
    0,
    reason:
        '$leakedPixels synthetic sensitive pixels survived masking in $name',
  );
  return {
    'name': name,
    'scroll_offset': scrollOffset,
    'animation_value': animationValue,
    'mask_count': capture.maskCount,
    'jpeg_width': decoded.width,
    'jpeg_height': decoded.height,
    'leaked_sensitive_pixels': leakedPixels,
  };
}

class _RafMonitor {
  JSObject? _probe;

  void start() {
    // Keep the per-frame callback entirely in JavaScript. Crossing from JS
    // into compiled Dart on every rAF materially perturbs old mobile browsers
    // and can make the measurement itself look like application jank.
    _probe = globalContext.callMethod<JSObject>(
      'eval'.toJS,
      '''(() => {
        const timestamps = [];
        let requestId = null;
        const onFrame = timestamp => {
          timestamps.push(timestamp);
          requestId = requestAnimationFrame(onFrame);
        };
        requestId = requestAnimationFrame(onFrame);
        return {
          stop: () => {
            if (requestId !== null) cancelAnimationFrame(requestId);
            return timestamps;
          }
        };
      })()'''
          .toJS,
    );
  }

  _FrameMetrics stop({
    List<int> captureTimesMs = const [],
    List<Map<String, int>> capturePhases = const [],
    double baselineMaxGapMs = 0,
    _LongTaskMetrics longTasks = const _LongTaskMetrics.unsupported(),
  }) {
    final timestamps = _probe!
        .callMethod<JSArray<JSNumber>>('stop'.toJS)
        .toDart
        .map((timestamp) => timestamp.toDartDouble)
        .toList(growable: false);
    _probe = null;
    final gaps = <double>[
      for (var i = 1; i < timestamps.length; i++)
        timestamps[i] - timestamps[i - 1],
    ]..sort();
    final maxGap = gaps.isEmpty ? 0.0 : gaps.last;
    final p95Index = gaps.isEmpty ? 0 : ((gaps.length - 1) * 0.95).round();
    final estimatedDroppedFrames = gaps.fold<int>(
      0,
      (total, gap) => total + math.max(0, (gap / (1000 / 60)).round() - 1),
    );
    return _FrameMetrics(
      sampleCount: gaps.length,
      maxGapMs: maxGap,
      p95GapMs: gaps.isEmpty ? 0 : gaps[p95Index],
      longFrameCount: gaps.where((gap) => gap > _longFrameThresholdMs).length,
      addedMaxGapMs: math.max(0, maxGap - baselineMaxGapMs),
      estimatedDroppedFrames: estimatedDroppedFrames,
      longTaskSupported: longTasks.supported,
      longTaskCount: longTasks.durationsMs.length,
      maxLongTaskMs: longTasks.durationsMs.isEmpty
          ? 0
          : longTasks.durationsMs.reduce(math.max),
      captureTimesMs: captureTimesMs,
      capturePhases: capturePhases,
    );
  }
}

class _LongTaskMonitor {
  final List<double> _durationsMs = [];
  web.PerformanceObserver? _observer;
  bool _supported = false;

  void start() {
    try {
      _supported = web.PerformanceObserver.supportedEntryTypes.toDart.any(
        (type) => type.toDart == 'longtask',
      );
      if (!_supported) return;

      void onEntries(
        web.PerformanceObserverEntryList list,
        web.PerformanceObserver observer,
      ) {
        _record(list.getEntries());
      }

      _observer = web.PerformanceObserver(onEntries.toJS)
        ..observe(web.PerformanceObserverInit(type: 'longtask'));
    } catch (_) {
      _supported = false;
      _observer = null;
    }
  }

  _LongTaskMetrics stop() {
    final observer = _observer;
    if (observer != null) {
      _record(observer.takeRecords());
      observer.disconnect();
      _observer = null;
    }
    return _LongTaskMetrics(
      supported: _supported,
      durationsMs: List.unmodifiable(_durationsMs),
    );
  }

  void _record(web.PerformanceEntryList entries) {
    for (final entry in entries.toDart) {
      _durationsMs.add(entry.duration);
    }
  }
}

class _LongTaskMetrics {
  const _LongTaskMetrics({required this.supported, required this.durationsMs});

  const _LongTaskMetrics.unsupported()
    : supported = false,
      durationsMs = const [];

  final bool supported;
  final List<double> durationsMs;
}

class _FrameMetrics {
  const _FrameMetrics({
    required this.sampleCount,
    required this.maxGapMs,
    required this.p95GapMs,
    required this.longFrameCount,
    required this.addedMaxGapMs,
    required this.estimatedDroppedFrames,
    required this.longTaskSupported,
    required this.longTaskCount,
    required this.maxLongTaskMs,
    required this.captureTimesMs,
    this.capturePhases = const [],
  });

  final int sampleCount;
  final double maxGapMs;
  final double p95GapMs;
  final int longFrameCount;
  final double addedMaxGapMs;
  final int estimatedDroppedFrames;
  final bool longTaskSupported;
  final int longTaskCount;
  final double maxLongTaskMs;
  final List<int> captureTimesMs;
  final List<Map<String, int>> capturePhases;

  Map<String, Object?> toJson() => {
    'raf_samples': sampleCount,
    'max_raf_gap_ms': maxGapMs,
    'p95_raf_gap_ms': p95GapMs,
    'long_frame_count': longFrameCount,
    'added_max_gap_ms': addedMaxGapMs,
    'estimated_dropped_frames': estimatedDroppedFrames,
    'long_task_api_supported': longTaskSupported,
    'long_task_count': longTaskCount,
    'max_long_task_ms': maxLongTaskMs,
    'capture_times_ms': captureTimesMs,
    if (capturePhases.isNotEmpty) 'capture_phases_ms': capturePhases,
  };
}

class _BoundaryHandle {
  const _BoundaryHandle({required this.boundary, required this.element});

  final RenderRepaintBoundary boundary;
  final Element element;
}

class _MotionMaskScene extends StatefulWidget {
  const _MotionMaskScene({super.key});

  @override
  State<_MotionMaskScene> createState() => _MotionMaskSceneState();
}

class _MotionMaskSceneState extends State<_MotionMaskScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  final ScrollController _scroll = ScrollController();

  double get animationValue => _motion.value;
  double get scrollOffset => _scroll.hasClients ? _scroll.offset : 0;

  void startMotion() {
    _motion.repeat(reverse: true);
    unawaited(
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(seconds: 8),
        curve: Curves.linear,
      ),
    );
  }

  void stopMotion() {
    _motion.stop();
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
  }

  void setPosition({
    required double animationValue,
    required double scrollFraction,
  }) {
    _motion.value = animationValue;
    _scroll.jumpTo(_scroll.position.maxScrollExtent * scrollFraction);
  }

  @override
  void dispose() {
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff10141c),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'LIVE MOTION MASK VALIDATION',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            SizedBox(
              height: 125,
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _motion,
                  builder: (context, child) => Stack(
                    children: [
                      Positioned(
                        left: 8 + _motion.value * (constraints.maxWidth - 152),
                        top: 8 + _motion.value * 25,
                        child: child!,
                      ),
                    ],
                  ),
                  child: _maskTarget('SECRET MOVING', width: 144, height: 76),
                ),
              ),
            ),
            const Divider(color: Colors.white54, height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemExtent: 104,
                itemCount: 30,
                itemBuilder: (context, index) => Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? const Color(0xff263347)
                        : const Color(0xff314056),
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          'ROW $index',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _maskTarget(
                            'SECRET ROW $index',
                            width: 180,
                            height: 62,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 38,
                        child: Icon(Icons.lock, color: Colors.lightBlueAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _maskTarget(
    String label, {
    required double width,
    required double height,
  }) {
    return MixpanelMask(
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        color: const Color(0xffff00ff),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _BenchmarkScene extends StatelessWidget {
  const _BenchmarkScene({required this.complexity});

  final int complexity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fa),
      body: Column(
        children: [
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff5b45e0), Color(0xff1598d4)],
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.analytics, color: Colors.white),
                SizedBox(width: 12),
                Text(
                  'Replay performance dashboard',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
                Spacer(),
                CircleAvatar(child: Text('TR')),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 150,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: complexity,
              itemBuilder: (context, index) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_graph,
                            color: Colors
                                .primaries[index % Colors.primaries.length],
                          ),
                          const Spacer(),
                          Text('${20 + index}%'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Metric $index',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: ((index % 9) + 1) / 10),
                      const Spacer(),
                      Text('Updated ${index + 1} minutes ago'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
