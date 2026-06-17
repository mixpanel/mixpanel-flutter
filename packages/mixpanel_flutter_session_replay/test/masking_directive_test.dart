import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';

void main() {
  group('MaskingDirective', () {
    group('shouldMask', () {
      test('masks text when text is in autoMaskTypes', () {
        // GIVEN
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text},
        );
        final bounds = Rect.fromLTWH(0, 0, 100, 50);

        // WHEN
        final result = directive.shouldMask(bounds, WidgetType.text);

        // THEN
        expect(result, true);
      });

      test('masks image when image is in autoMaskTypes', () {
        // GIVEN
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.image},
        );
        final bounds = Rect.fromLTWH(0, 0, 100, 50);

        // WHEN
        final result = directive.shouldMask(bounds, WidgetType.image);

        // THEN
        expect(result, true);
      });

      test('does not mask text when text is not in autoMaskTypes', () {
        // GIVEN
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.image},
        );
        final bounds = Rect.fromLTWH(0, 0, 100, 50);

        // WHEN
        final result = directive.shouldMask(bounds, WidgetType.text);

        // THEN
        expect(result, false);
      });

      test('does not mask other widget type', () {
        // GIVEN
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text, AutoMaskedView.image},
        );
        final bounds = Rect.fromLTWH(0, 0, 100, 50);

        // WHEN
        final result = directive.shouldMask(bounds, WidgetType.other);

        // THEN
        expect(result, false);
      });

      test('does not mask when autoMaskTypes is empty', () {
        // GIVEN
        final directive = MaskingDirective(autoMaskTypes: {});
        final bounds = Rect.fromLTWH(0, 0, 100, 50);

        // WHEN
        final textResult = directive.shouldMask(bounds, WidgetType.text);
        final imageResult = directive.shouldMask(bounds, WidgetType.image);

        // THEN
        expect(textResult, false);
        expect(imageResult, false);
      });

      test('manual unmask overrides auto-mask (highest precedence)', () {
        // GIVEN
        final unmaskBounds = Rect.fromLTWH(0, 0, 200, 200);
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text},
          unmaskedRegions: [MaskRegion(unmaskBounds, 42)],
        );
        final widgetBounds = Rect.fromLTWH(10, 10, 50, 20);

        // WHEN - widget is inside unmask region
        final result = directive.shouldMask(widgetBounds, WidgetType.text);

        // THEN
        expect(result, false);
      });

      test('manual mask overrides auto-mask rules', () {
        // GIVEN
        final maskBounds = Rect.fromLTWH(0, 0, 200, 200);
        final directive = MaskingDirective(
          autoMaskTypes: {}, // No auto-masking
          manualMaskRegions: [MaskRegion(maskBounds, 42)],
        );
        final widgetBounds = Rect.fromLTWH(10, 10, 50, 20);

        // WHEN - widget is inside manual mask region
        final result = directive.shouldMask(widgetBounds, WidgetType.other);

        // THEN
        expect(result, true);
      });

      test('manual unmask takes precedence over manual mask', () {
        // GIVEN
        final regionBounds = Rect.fromLTWH(0, 0, 200, 200);
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text},
          manualMaskRegions: [MaskRegion(regionBounds, 1)],
          unmaskedRegions: [MaskRegion(regionBounds, 2)],
        );
        final widgetBounds = Rect.fromLTWH(10, 10, 50, 20);

        // WHEN
        final result = directive.shouldMask(widgetBounds, WidgetType.text);

        // THEN - unmask wins (highest precedence)
        expect(result, false);
      });

      test('isInsideUnmask prevents auto-masking', () {
        // GIVEN
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text},
        );
        final bounds = Rect.fromLTWH(0, 0, 100, 50);

        // WHEN
        final result = directive.shouldMask(
          bounds,
          WidgetType.text,
          isInsideUnmask: true,
        );

        // THEN
        expect(result, false);
      });

      test('isInsideUnmask does not override manual mask', () {
        // GIVEN
        final maskBounds = Rect.fromLTWH(0, 0, 200, 200);
        final directive = MaskingDirective(
          autoMaskTypes: {},
          manualMaskRegions: [MaskRegion(maskBounds, 42)],
        );
        final widgetBounds = Rect.fromLTWH(10, 10, 50, 20);

        // WHEN
        final result = directive.shouldMask(
          widgetBounds,
          WidgetType.text,
          isInsideUnmask: true,
        );

        // THEN - manual mask still applies
        expect(result, true);
      });
    });

    group('copyWith', () {
      test('creates copy with updated autoMaskTypes', () {
        // GIVEN
        final original = MaskingDirective(autoMaskTypes: {AutoMaskedView.text});
        final expectedTypes = {AutoMaskedView.image};

        // WHEN
        final copy = original.copyWith(autoMaskTypes: expectedTypes);

        // THEN
        expect(copy.autoMaskTypes, expectedTypes);
        expect(copy.manualMaskRegions, original.manualMaskRegions);
        expect(copy.unmaskedRegions, original.unmaskedRegions);
      });

      test('preserves original values when not overridden', () {
        // GIVEN
        final maskRegion = MaskRegion(Rect.fromLTWH(0, 0, 100, 100), 1);
        final unmaskRegion = MaskRegion(Rect.fromLTWH(50, 50, 30, 30), 2);
        final original = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text},
          manualMaskRegions: [maskRegion],
          unmaskedRegions: [unmaskRegion],
        );

        // WHEN
        final copy = original.copyWith();

        // THEN
        expect(copy.autoMaskTypes, original.autoMaskTypes);
        expect(copy.manualMaskRegions, original.manualMaskRegions);
        expect(copy.unmaskedRegions, original.unmaskedRegions);
      });
    });

    group('toString', () {
      test('includes auto mask types and region counts', () {
        // GIVEN
        final directive = MaskingDirective(
          autoMaskTypes: {AutoMaskedView.text, AutoMaskedView.image},
          manualMaskRegions: [MaskRegion(Rect.fromLTWH(0, 0, 100, 100), 1)],
          unmaskedRegions: [
            MaskRegion(Rect.fromLTWH(50, 50, 30, 30), 2),
            MaskRegion(Rect.fromLTWH(80, 80, 20, 20), 3),
          ],
        );

        // WHEN
        final result = directive.toString();

        // THEN
        expect(result, contains('manualMasks: 1'));
        expect(result, contains('unmasks: 2'));
      });
    });
  });

  group('MaskRegionInfo', () {
    test('stores bounds and source', () {
      // GIVEN
      final expectedBounds = Rect.fromLTWH(10, 20, 100, 50);
      final expectedSource = MaskSource.auto;

      // WHEN
      final info = MaskRegionInfo(expectedBounds, expectedSource);

      // THEN
      expect(info.bounds, expectedBounds);
      expect(info.source, expectedSource);
    });

    test('toString includes bounds and source', () {
      // GIVEN
      final info = MaskRegionInfo(
        Rect.fromLTWH(10, 20, 100, 50),
        MaskSource.security,
      );

      // WHEN
      final result = info.toString();

      // THEN
      expect(result, contains('MaskRegionInfo'));
      expect(result, contains('security'));
    });
  });

  group('MaskRegion', () {
    test('contains returns true for overlapping rect', () {
      // GIVEN
      final region = MaskRegion(Rect.fromLTWH(0, 0, 100, 100), 42);
      final overlapping = Rect.fromLTWH(50, 50, 80, 80);

      // WHEN
      final result = region.contains(overlapping);

      // THEN
      expect(result, true);
    });

    test('contains returns false for non-overlapping rect', () {
      // GIVEN
      final region = MaskRegion(Rect.fromLTWH(0, 0, 100, 100), 42);
      final nonOverlapping = Rect.fromLTWH(200, 200, 50, 50);

      // WHEN
      final result = region.contains(nonOverlapping);

      // THEN
      expect(result, false);
    });

    test('toString includes bounds and hash', () {
      // GIVEN
      final region = MaskRegion(Rect.fromLTWH(0, 0, 100, 100), 42);

      // WHEN
      final result = region.toString();

      // THEN
      expect(result, contains('MaskRegion'));
      expect(result, contains('42'));
    });
  });
}
