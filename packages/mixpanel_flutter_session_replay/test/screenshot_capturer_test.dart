import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/screenshot_capturer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/wireframe/wireframe_emitter.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';

import 'utils/golden_test_utils.dart';

void main() {
  group('ScreenshotCapturer wireframe kill switch', () {
    final logger = MixpanelLogger(LogLevel.none);

    ScreenshotCapturer createCapturer({required bool withEmitter}) =>
        ScreenshotCapturer(
          directive: MaskingDirective(autoMaskTypes: {}),
          logger: logger,
          debugOverlayEnabled: false,
          compressionMode: CompressionMode.dartPng,
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
        () =>
            capturer.capture(target.boundary, boundaryElement: target.element),
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
  });
}
