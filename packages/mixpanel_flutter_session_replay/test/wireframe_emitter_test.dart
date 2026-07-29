import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/wireframe/wireframe_emitter.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframe.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframes_options.dart';

void main() {
  final logger = MixpanelLogger(LogLevel.none);
  final defaultTimestamp = DateTime.fromMillisecondsSinceEpoch(
    1000,
    isUtc: true,
  );
  const defaultViewport = Size(400, 800);

  WireframeElement el({
    WireframeRole role = WireframeRole.text,
    String? text = 'hello',
    Rect bounds = const Rect.fromLTWH(0, 0, 100, 20),
    MaskDecision maskDecision = MaskDecision.none,
  }) => WireframeElement(
    role: role,
    text: text,
    bounds: bounds,
    maskDecision: maskDecision,
  );

  group('WireframeEmitter — passthrough', () {
    test('emits elements unchanged when no rules and no mask overlap', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(text: 'Hello world')];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload, isNotNull);
      expect(payload!.viewportWidth, 400);
      expect(payload.viewportHeight, 800);
      expect(payload.elements.single.text, 'Hello world');
      expect(payload.elements.single.maskDecision, MaskDecision.none);
    });
  });

  group('WireframeEmitter — geometric masking', () {
    test('nulls text when bounds intersect any mask region', () {
      // GIVEN — element at (10,10,100,20); mask at (50,10,60,20) → overlaps
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(bounds: const Rect.fromLTWH(10, 10, 100, 20))];
      final masks = [
        MaskRegionInfo(const Rect.fromLTWH(50, 10, 60, 20), MaskSource.auto),
      ];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: masks,
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, isNull);
      expect(payload.elements.single.maskDecision, MaskDecision.geometric);
    });

    test('leaves element alone when bounds do not intersect', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(bounds: const Rect.fromLTWH(10, 10, 40, 20))];
      final masks = [
        MaskRegionInfo(const Rect.fromLTWH(200, 200, 40, 20), MaskSource.auto),
      ];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: masks,
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, 'hello');
    });

    test('does not run for elements already decided by the mask detector', () {
      // GIVEN — element with decision != none should not be re-marked GEOMETRIC
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );
      final input = [
        el(
          text: null,
          maskDecision: MaskDecision.explicit,
          bounds: const Rect.fromLTWH(0, 0, 100, 100),
        ),
      ];
      final masks = [
        MaskRegionInfo(const Rect.fromLTWH(0, 0, 100, 100), MaskSource.manual),
      ];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: masks,
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN — decision preserved
      expect(payload!.elements.single.maskDecision, MaskDecision.explicit);
    });
  });

  group('WireframeEmitter — user rules', () {
    test('StripRule nulls text and short-circuits later rules', () {
      // GIVEN — StripRule precedes RedactRule; the RedactRule must NOT run
      final emitter = WireframeEmitter(
        sensitiveRules: const [StripRule('password'), RedactRule('field')],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(text: 'my password field')];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, isNull);
      expect(payload.elements.single.maskDecision, MaskDecision.ruleStrip);
    });

    test('StripRule is case-insensitive substring match', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [StripRule('BEARER ')],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(text: 'header: bearer abc.def.ghi')];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, isNull);
      expect(payload.elements.single.maskDecision, MaskDecision.ruleStrip);
    });

    test(
      'RedactRule rewrites in place and the next rule sees rewritten value',
      () {
        // GIVEN — first RedactRule rewrites email; second StripRule matches the redacted
        // token so we can verify the second rule ran against the rewritten text.
        final emitter = WireframeEmitter(
          sensitiveRules: const [
            RedactRule('foo@bar.com', replacement: '[EMAIL]'),
            StripRule('[EMAIL]'),
          ],
          debugEmitter: null,
          logger: logger,
        );
        final input = [el(text: 'contact foo@bar.com now')];

        // WHEN
        final payload = emitter.emit(
          rawElements: input,
          maskRegions: const [],
          viewport: defaultViewport,
          timestamp: defaultTimestamp,
        );

        // THEN — StripRule on rewritten value wins over the RedactRule
        expect(payload!.elements.single.text, isNull);
        expect(payload.elements.single.maskDecision, MaskDecision.ruleStrip);
      },
    );

    test('RedactRule-only leaves rewritten text with ruleRedact decision', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [RedactRule('secret', replacement: '***')],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(text: 'my Secret is safe')];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN — case-insensitive replace preserves surrounding text
      expect(payload!.elements.single.text, 'my *** is safe');
      expect(payload.elements.single.maskDecision, MaskDecision.ruleRedact);
    });

    test('RedactRegexRule rewrites all matches', () {
      // GIVEN — SSN pattern
      final emitter = WireframeEmitter(
        sensitiveRules: [
          RedactRegexRule(RegExp(r'\d{3}-\d{2}-\d{4}'), replacement: '[SSN]'),
        ],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(text: 'SSN 123-45-6789 and 987-65-4321')];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, 'SSN [SSN] and [SSN]');
      expect(payload.elements.single.maskDecision, MaskDecision.ruleRedact);
    });

    test('StripRegexRule nulls text on match', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: [StripRegexRule(RegExp(r'^token-'))],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(text: 'token-abcdef')];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, isNull);
      expect(payload.elements.single.maskDecision, MaskDecision.ruleStrip);
    });

    test('rules do not run for elements already decided upstream', () {
      // GIVEN — element already textEntry from the mask detector
      final emitter = WireframeEmitter(
        sensitiveRules: const [RedactRule('will-not-match')],
        debugEmitter: null,
        logger: logger,
      );
      final input = [
        el(
          text: null,
          maskDecision: MaskDecision.textEntry,
          role: WireframeRole.input,
        ),
      ];

      // WHEN
      final payload = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.maskDecision, MaskDecision.textEntry);
    });
  });

  group('WireframeEmitter — truncation', () {
    test('truncates text longer than 60 chars with ellipsis', () {
      // GIVEN — 70 char string
      final long = 'a' * 70;
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );

      // WHEN
      final payload = emitter.emit(
        rawElements: [el(text: long)],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(
        payload!.elements.single.text!.length,
        WireframeConstants.maxTextLength + 1,
      );
      expect(payload.elements.single.text!.endsWith('…'), isTrue);
    });

    test('leaves 60-char text unchanged', () {
      // GIVEN — exactly 60 chars
      final exact = 'b' * 60;
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );

      // WHEN
      final payload = emitter.emit(
        rawElements: [el(text: exact)],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements.single.text, exact);
    });
  });

  group('WireframeEmitter — noise drop', () {
    WireframeEmitter freshEmitter() => WireframeEmitter(
      sensitiveRules: const [],
      debugEmitter: null,
      logger: logger,
    );

    test('keeps element with mask decision != none even when text is null', () {
      // GIVEN — masked text field: no text but the mask decision IS the signal
      final payload = freshEmitter().emit(
        rawElements: [
          el(
            role: WireframeRole.input,
            text: null,
            maskDecision: MaskDecision.textEntry,
          ),
        ],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements, hasLength(1));
    });

    test('drops element with mask decision none and null text', () {
      // GIVEN — unmasked image with no semantic label
      final payload = freshEmitter().emit(
        rawElements: [el(role: WireframeRole.image, text: null)],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN — deduped to null (only element was noise)
      expect(payload, isNull);
    });

    test('drops element with mask decision none and empty text', () {
      // GIVEN
      final payload = freshEmitter().emit(
        rawElements: [el(text: '')],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload, isNull);
    });

    test('drops element whose text is only unicode private-use glyphs', () {
      // GIVEN — icon-only button rendered as a Material Icons codepoint
      final payload = freshEmitter().emit(
        rawElements: [
          el(role: WireframeRole.button, text: String.fromCharCode(0xe57f)),
        ],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload, isNull);
    });

    test('keeps element with mixed glyph + regular text', () {
      // GIVEN — a button labeled "Settings ⚙" (glyph + real text)
      final payload = freshEmitter().emit(
        rawElements: [
          el(
            role: WireframeRole.button,
            text: 'Settings ${String.fromCharCode(0xe57f)}',
          ),
        ],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(payload!.elements, hasLength(1));
    });
  });

  group('WireframeEmitter — dedup', () {
    test('skips emit when consecutive frames are identical', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el()];

      // WHEN
      final first = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );
      final second = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(first, isNotNull);
      expect(second, isNull);
    });

    test('emits again when elements change', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );

      // WHEN
      final first = emitter.emit(
        rawElements: [el(text: 'a')],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );
      final second = emitter.emit(
        rawElements: [el(text: 'b')],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(first, isNotNull);
      expect(second, isNotNull);
    });

    test('emits again when mask regions change', () {
      // GIVEN
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: null,
        logger: logger,
      );
      final input = [el(bounds: const Rect.fromLTWH(0, 0, 10, 10))];

      // WHEN — same elements, different mask sets
      final first = emitter.emit(
        rawElements: input,
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );
      final second = emitter.emit(
        rawElements: input,
        maskRegions: [
          MaskRegionInfo(
            const Rect.fromLTWH(500, 500, 10, 10),
            MaskSource.auto,
          ),
        ],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(first, isNotNull);
      expect(second, isNotNull);
    });
  });

  group('WireframeEmitter — debug callback', () {
    test('invokes callback exactly once per successful emit', () {
      // GIVEN
      final received = <WireframeSnapshot>[];
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: received.add,
        logger: logger,
      );

      // WHEN
      emitter.emit(
        rawElements: [el()],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(received, hasLength(1));
      expect(received.single.viewport, [400, 800]);
      expect(received.single.elements, hasLength(1));
      expect(received.single.elements.single.role, 'text');
    });

    test('does not invoke callback when frame is deduped', () {
      // GIVEN
      final received = <WireframeSnapshot>[];
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: received.add,
        logger: logger,
      );

      // WHEN — same input twice
      emitter.emit(
        rawElements: [el()],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );
      emitter.emit(
        rawElements: [el()],
        maskRegions: const [],
        viewport: defaultViewport,
        timestamp: defaultTimestamp,
      );

      // THEN
      expect(received, hasLength(1));
    });

    test('swallows exceptions thrown from the callback', () {
      // GIVEN — callback throws
      final emitter = WireframeEmitter(
        sensitiveRules: const [],
        debugEmitter: (_) => throw StateError('boom'),
        logger: logger,
      );

      // WHEN / THEN — emit does not throw
      expect(
        () => emitter.emit(
          rawElements: [el()],
          maskRegions: const [],
          viewport: defaultViewport,
          timestamp: defaultTimestamp,
        ),
        returnsNormally,
      );
    });
  });
}
