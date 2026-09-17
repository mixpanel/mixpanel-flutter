import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';

void main() {
  testWidgets('should skip capture when a route transition is in progress', (
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

  testWidgets(
    'should preserve name matching when a custom render type is used',
    (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: const _CompatibilityTextRenderObjectWidget(),
        ),
      );

      final boundaryElement = boundaryKey.currentContext! as Element;
      final boundary = boundaryElement.renderObject! as RenderRepaintBoundary;
      final directive = MaskingDirective(
        autoMaskTypes: const {AutoMaskedView.text},
      );
      final result = MaskDetector(
        directive: directive,
      ).detectMaskRegions(boundary, boundaryElement: boundaryElement);

      expect(result.maskRegions, hasLength(1));
      expect(result.maskRegions.single.source, MaskSource.auto);
    },
  );
}

class _CompatibilityTextRenderObjectWidget extends LeafRenderObjectWidget {
  const _CompatibilityTextRenderObjectWidget();

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderParagraphCompatibilityProxy();
  }
}

class _RenderParagraphCompatibilityProxy extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size(100, 40));
  }
}
