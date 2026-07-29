import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframes_options.dart';

void main() {
  group('WireframesOptions', () {
    test('has empty rules and null callback by default', () {
      // WHEN
      const options = WireframesOptions();

      // THEN
      expect(options.sensitiveRules, isEmpty);
      expect(options.debugEmitter, isNull);
    });

    test('carries provided rules and callback', () {
      // GIVEN
      final rules = [const StripRule('password'), const RedactRule('email')];
      void callback(WireframeSnapshot _) {}

      // WHEN
      final options = WireframesOptions(
        sensitiveRules: rules,
        debugEmitter: callback,
      );

      // THEN
      expect(options.sensitiveRules, same(rules));
      expect(options.debugEmitter, same(callback));
    });
  });

  group('SensitiveRule variants', () {
    test('RedactRule defaults replacement to [REDACTED]', () {
      const rule = RedactRule('secret');
      expect(rule.text, 'secret');
      expect(rule.replacement, '[REDACTED]');
    });

    test('RedactRule accepts custom replacement', () {
      const rule = RedactRule('email', replacement: '[EMAIL]');
      expect(rule.replacement, '[EMAIL]');
    });

    test('StripRule carries only text', () {
      const rule = StripRule('token');
      expect(rule.text, 'token');
    });

    test('RedactRegexRule defaults replacement to [REDACTED]', () {
      final rule = RedactRegexRule(RegExp(r'\d+'));
      expect(rule.regex.pattern, r'\d+');
      expect(rule.replacement, '[REDACTED]');
    });

    test('StripRegexRule carries only regex', () {
      final rule = StripRegexRule(RegExp('secret'));
      expect(rule.regex.pattern, 'secret');
    });
  });

  group('WireframeSnapshot', () {
    test('toJson produces expected shape with wire-format decision names', () {
      // GIVEN
      const snapshot = WireframeSnapshot(
        timestamp: 1_749_317_600_000,
        viewport: [1080, 1920],
        elements: [
          WireframeSnapshotElement(
            role: 'text',
            text: 'Welcome',
            bounds: [24, 120, 400, 40],
            maskDecision: MaskDecision.none,
          ),
          WireframeSnapshotElement(
            role: 'input',
            text: null,
            bounds: [40, 600, 400, 48],
            maskDecision: MaskDecision.textEntry,
          ),
          WireframeSnapshotElement(
            role: 'text',
            text: null,
            bounds: [0, 0, 10, 10],
            maskDecision: MaskDecision.geometric,
          ),
        ],
      );

      // WHEN
      final decoded = jsonDecode(snapshot.toJson()) as Map<String, dynamic>;

      // THEN
      expect(decoded['timestamp'], 1_749_317_600_000);
      expect(decoded['viewport'], [1080, 1920]);
      final elements = decoded['elements'] as List;
      expect(elements, hasLength(3));
      expect(elements[0]['role'], 'text');
      expect(elements[0]['text'], 'Welcome');
      expect(elements[0]['bounds'], [24, 120, 400, 40]);
      expect(elements[0]['maskDecision'], 'NONE');
      expect(elements[1]['text'], isNull);
      expect(elements[1]['maskDecision'], 'TEXT_ENTRY');
      expect(elements[2]['maskDecision'], 'GEOMETRIC');
    });

    test('toJson serializes every MaskDecision variant', () {
      // GIVEN — one element per enum value
      final elements = MaskDecision.values
          .map(
            (d) => WireframeSnapshotElement(
              role: 'text',
              text: null,
              bounds: const [0, 0, 1, 1],
              maskDecision: d,
            ),
          )
          .toList();
      final snapshot = WireframeSnapshot(
        timestamp: 0,
        viewport: const [0, 0],
        elements: elements,
      );

      // WHEN
      final decoded = jsonDecode(snapshot.toJson()) as Map<String, dynamic>;

      // THEN — all wire names present, no lowercase enum names
      final names = (decoded['elements'] as List)
          .map((e) => (e as Map)['maskDecision'] as String)
          .toList();
      expect(names, [
        'NONE',
        'EXPLICIT',
        'AUTO',
        'TEXT_ENTRY',
        'GEOMETRIC',
        'RULE_STRIP',
        'RULE_REDACT',
      ]);
    });
  });
}
