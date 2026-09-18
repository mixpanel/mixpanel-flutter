@TestOn('browser')
library;

import 'dart:ui' show Color, Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/debug_overlay_host.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/debug_overlay_host_web.dart'
    as impl;
import 'package:mixpanel_flutter_session_replay/src/models/debug_overlay_colors.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:web/web.dart' as web;

void main() {
  const containerId = 'mp-session-replay-debug-overlay';
  const boundarySize = Size(400, 300);

  DebugOverlayHost? host;

  web.HTMLElement? container() =>
      web.document.getElementById(containerId) as web.HTMLElement?;

  List<web.HTMLElement> regionNodes() {
    final children = container()!.children;
    return [
      for (var index = 0; index < children.length; index++)
        children.item(index)! as web.HTMLElement,
    ];
  }

  void draw(
    List<MaskRegionInfo> regions, {
    DebugOverlayColors colors = const DebugOverlayColors(),
  }) {
    host!.update(
      regions: regions,
      colors: colors,
      boundaryOrigin: Offset.zero,
      boundarySize: boundarySize,
    );
  }

  setUp(() => host = impl.createDebugOverlayHost());

  tearDown(() {
    host?.dispose();
    host = null;
  });

  test('draws regions outside any canvas the capture could select', () {
    // GIVEN - WebImageCompressor skips the frame when more than one canvas
    // under a Flutter engine host matches the viewport
    // WHEN
    draw([MaskRegionInfo(const Rect.fromLTWH(0, 0, 10, 10), MaskSource.auto)]);

    // THEN
    expect(container(), isNotNull);
    expect(container()!.querySelectorAll('canvas').length, 0);
    expect(container()!.querySelectorAll('flt-platform-view').length, 0);
    expect(container()!.style.pointerEvents, 'none');
  });

  test('positions each region in logical pixels', () {
    // GIVEN - WHEN
    draw([
      MaskRegionInfo(const Rect.fromLTWH(12, 34, 56, 78), MaskSource.manual),
    ]);

    // THEN
    final node = regionNodes().single;
    expect(node.style.left, '12px');
    expect(node.style.top, '34px');
    expect(node.style.width, '56px');
    expect(node.style.height, '78px');
  });

  test('composites opaque regions under a single group opacity', () {
    // GIVEN - overlapping regions must not compound their transparency
    // WHEN
    draw(
      [
        MaskRegionInfo(const Rect.fromLTWH(0, 0, 10, 10), MaskSource.manual),
        MaskRegionInfo(const Rect.fromLTWH(5, 5, 10, 10), MaskSource.manual),
      ],
      colors: const DebugOverlayColors(
        maskColor: Color(0xFF112233),
        opacity: 0.25,
      ),
    );

    // THEN
    expect(container()!.style.opacity, '0.25');
    for (final node in regionNodes()) {
      // Browsers serialize a fully opaque color as rgb(); anything less than
      // full alpha here would come back as rgba() and compound on overlap.
      expect(node.style.backgroundColor, 'rgb(17, 34, 51)');
    }
  });

  test('orders unmask below auto below manual', () {
    // GIVEN - WHEN
    draw([
      MaskRegionInfo(const Rect.fromLTWH(3, 0, 1, 1), MaskSource.manual),
      MaskRegionInfo(const Rect.fromLTWH(1, 0, 1, 1), MaskSource.unmask),
      MaskRegionInfo(const Rect.fromLTWH(4, 0, 1, 1), MaskSource.security),
      MaskRegionInfo(const Rect.fromLTWH(2, 0, 1, 1), MaskSource.auto),
    ]);

    // THEN - DOM order is paint order
    expect(regionNodes().map((node) => node.style.left), [
      '1px',
      '2px',
      '3px',
      '4px',
    ]);
  });

  test('omits sources whose visualization color is null', () {
    // GIVEN - WHEN
    draw([
      MaskRegionInfo(const Rect.fromLTWH(1, 0, 1, 1), MaskSource.auto),
      MaskRegionInfo(const Rect.fromLTWH(2, 0, 1, 1), MaskSource.manual),
    ], colors: const DebugOverlayColors(autoMaskColor: null));

    // THEN
    expect(regionNodes().map((node) => node.style.left), ['2px']);
  });

  test('releases nodes when the region count drops', () {
    // GIVEN
    draw([
      MaskRegionInfo(const Rect.fromLTWH(1, 0, 1, 1), MaskSource.auto),
      MaskRegionInfo(const Rect.fromLTWH(2, 0, 1, 1), MaskSource.auto),
      MaskRegionInfo(const Rect.fromLTWH(3, 0, 1, 1), MaskSource.auto),
    ]);
    expect(regionNodes(), hasLength(3));

    // WHEN - recording stopped, so the coordinator clears the regions
    draw(const []);

    // THEN
    expect(regionNodes(), isEmpty);
  });

  test('replaces an overlay left behind by a previous isolate', () {
    // GIVEN - a hot restart leaves the old container in the document
    draw([MaskRegionInfo(const Rect.fromLTWH(1, 0, 1, 1), MaskSource.auto)]);
    final stale = container();

    // WHEN
    final restarted = impl.createDebugOverlayHost()!;
    addTearDown(restarted.dispose);
    restarted.update(
      regions: [
        MaskRegionInfo(const Rect.fromLTWH(2, 0, 1, 1), MaskSource.auto),
      ],
      colors: const DebugOverlayColors(),
      boundaryOrigin: Offset.zero,
      boundarySize: boundarySize,
    );

    // THEN - exactly one overlay remains, and it is the new one
    expect(web.document.querySelectorAll('#$containerId').length, 1);
    expect(container(), isNot(same(stale)));
    expect(regionNodes().map((node) => node.style.left), ['2px']);
  });

  test('removes the overlay on dispose', () {
    // GIVEN
    draw([MaskRegionInfo(const Rect.fromLTWH(1, 0, 1, 1), MaskSource.auto)]);
    expect(container(), isNotNull);

    // WHEN
    host!.dispose();

    // THEN
    expect(container(), isNull);
  });
}
