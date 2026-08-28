import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframe.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/mask_widget.dart';

/// The accessibility-label fallback, asserted at the detector rather than through
/// a golden.
///
/// A golden cannot pin this. `MixpanelMask` always records a mask region, and the
/// emitter's geometric pass strips the button's text whenever a region overlaps —
/// which it does in every arrangement, because the region is recorded from the
/// masked subtree's layout position. So the end-to-end output is textless with or
/// without the fix, and a golden would pass either way while pinning nothing.
///
/// `rawWireframes` is the detector's output *before* Layer 2 runs, so asserting
/// there isolates the layer that decides whether a label may be harvested at all.
/// That distinction matters: Layer 2 can only strip what it can intersect, and a
/// masked contributor that is clipped, scrolled out of the viewport, or otherwise
/// without a rect gives it nothing to catch.
void main() {
  Future<List<WireframeElement>> collect(
    WidgetTester tester,
    Widget widget, {
    Set<AutoMaskedView> autoMask = const {},
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: RepaintBoundary(child: widget)),
        ),
      ),
    );
    await tester.pump();

    final boundary = tester.allRenderObjects
        .whereType<RenderRepaintBoundary>()
        .first;
    final detector = MaskDetector(
      directive: MaskingDirective(autoMaskTypes: autoMask),
      trackUnmaskBounds: false,
      collectWireframes: true,
      useAccessibilityLabelFallback: true,
    );
    return detector.detectMaskRegions(boundary).rawWireframes ?? const [];
  }

  WireframeElement buttonOf(List<WireframeElement> elements) =>
      elements.firstWhere((e) => e.role == WireframeRole.button);

  group('accessibility label fallback respects descendant masking', () {
    testWidgets('a masked Semantics label is not harvested by its button', (
      tester,
    ) async {
      final elements = await collect(
        tester,
        IconButton(
          onPressed: () {},
          icon: MixpanelMask(
            child: Semantics(
              image: true,
              label: 'Photo of Jane Doe',
              child: const SizedBox(width: 24, height: 24),
            ),
          ),
        ),
      );

      expect(buttonOf(elements).text, isNull);
    });

    testWidgets('a masked Tooltip message is not harvested by its button', (
      tester,
    ) async {
      final elements = await collect(
        tester,
        IconButton(
          onPressed: () {},
          icon: MixpanelMask(
            child: Tooltip(
              message: 'Delete account for jane@example.com',
              child: const SizedBox(width: 24, height: 24),
            ),
          ),
        ),
      );

      expect(buttonOf(elements).text, isNull);
    });

    testWidgets('an unmasked label is still harvested', (tester) async {
      // The guard must not swallow the feature it guards: with nothing masked,
      // the fallback still names an icon-only button.
      final elements = await collect(
        tester,
        IconButton(
          onPressed: () {},
          icon: Semantics(
            image: true,
            label: 'Add item',
            child: const SizedBox(width: 24, height: 24),
          ),
        ),
      );

      expect(buttonOf(elements).text, 'Add item');
    });
  });
}
