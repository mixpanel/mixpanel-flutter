import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';

void main() {
  testWidgets('detects route transitions during the mask traversal', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('First route')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundaryElement = boundaryKey.currentContext! as Element;
    final boundary = boundaryElement.renderObject! as RenderRepaintBoundary;
    final detector = MaskDetector(
      directive: MaskingDirective(autoMaskTypes: const {}),
    );

    expect(
      detector
          .detectMaskRegions(boundary, boundaryElement: boundaryElement)
          .shouldSkipCapture,
      isFalse,
    );

    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Second route')),
        ),
      ),
    );
    await tester.pump();

    expect(
      detector
          .detectMaskRegions(boundary, boundaryElement: boundaryElement)
          .shouldSkipCapture,
      isTrue,
    );

    await tester.pumpAndSettle();
    expect(
      detector
          .detectMaskRegions(boundary, boundaryElement: boundaryElement)
          .shouldSkipCapture,
      isFalse,
    );
  });
}
