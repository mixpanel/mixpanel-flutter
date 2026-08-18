@Tags(['golden'])
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframes_options.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/widgets.dart';

import 'utils/golden_test_utils.dart';

void main() {
  group('WireframeGolden — text mask decisions', () {
    testWidgets('plain text is emitted verbatim when no rules apply', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        const Text('Public Information'),
        'wireframe_text_plain.json',
        {},
      );
    });

    testWidgets('text under AutoMaskedView.text is nulled with auto decision', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        const Text('Sensitive Information'),
        'wireframe_text_auto_masked.json',
        {AutoMaskedView.text},
      );
    });

    testWidgets('text under MixpanelMask is nulled with explicit decision', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        const MixpanelMask(child: Text('Sensitive Information')),
        'wireframe_text_explicit_masked.json',
        {},
      );
    });

    testWidgets('text under MixpanelUnmask overrides auto-mask', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        const MixpanelUnmask(child: Text('Public Override')),
        'wireframe_text_unmask_overrides_auto.json',
        {AutoMaskedView.text},
      );
    });
  });

  group('WireframeGolden — text-entry fields', () {
    testWidgets('TextField is always masked (textEntry)', (tester) async {
      await captureWireframeGolden(
        tester,
        TextField(controller: TextEditingController(text: 'user@example.com')),
        'wireframe_textfield_always_masked.json',
        {},
      );
    });

    testWidgets(
      'TextField inside MixpanelUnmask stays masked (security override)',
      (tester) async {
        await captureWireframeGolden(
          tester,
          MixpanelUnmask(
            child: TextField(
              controller: TextEditingController(text: 'password123'),
            ),
          ),
          'wireframe_textfield_in_unmask_still_masked.json',
          {AutoMaskedView.text},
        );
      },
    );

    testWidgets('CupertinoTextField is always masked (textEntry)', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        CupertinoTextField(
          controller: TextEditingController(text: 'secret-value'),
        ),
        'wireframe_cupertino_textfield_always_masked.json',
        {},
      );
    });
  });

  group('WireframeGolden — buttons', () {
    testWidgets('ElevatedButton is emitted as role button', (tester) async {
      await captureWireframeGolden(
        tester,
        ElevatedButton(onPressed: () {}, child: const Text('Submit')),
        'wireframe_elevated_button.json',
        {},
      );
    });

    testWidgets('TextButton is emitted as role button', (tester) async {
      await captureWireframeGolden(
        tester,
        TextButton(onPressed: () {}, child: const Text('Cancel')),
        'wireframe_text_button.json',
        {},
      );
    });

    testWidgets('IconButton without a label emits a textless button shell', (
      tester,
    ) async {
      // The icon renders as a Material Icons private-use codepoint, which is
      // not human-readable text. Per the Wireframe Capture Contract the glyph
      // is nulled but the button shell (role + bounds) is still emitted.
      await captureWireframeGolden(
        tester,
        IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
        'wireframe_icon_button_unlabeled.json',
        {},
      );
    });

    testWidgets('IconButton falls back to its tooltip as the button label', (
      tester,
    ) async {
      // No visible text, but the Tooltip message is an accessibility label the
      // AI can use. Unmasked → the shell carries the tooltip text.
      await captureWireframeGolden(
        tester,
        IconButton(
          onPressed: () {},
          tooltip: 'Open settings',
          icon: const Icon(Icons.settings),
        ),
        'wireframe_icon_button_tooltip_label.json',
        {},
      );
    });

    testWidgets('IconButton falls back to the Icon semanticLabel', (
      tester,
    ) async {
      // The icon exposes a semanticLabel; with no visible text and no tooltip
      // it becomes the button label.
      await captureWireframeGolden(
        tester,
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.add, semanticLabel: 'Add item'),
        ),
        'wireframe_icon_button_semantic_label.json',
        {},
      );
    });

    testWidgets('CupertinoButton is emitted as role button', (tester) async {
      await captureWireframeGolden(
        tester,
        CupertinoButton(onPressed: () {}, child: const Text('Confirm')),
        'wireframe_cupertino_button.json',
        {},
      );
    });

    testWidgets(
      'FloatingActionButton with only an icon emits a textless button shell',
      (tester) async {
        await captureWireframeGolden(
          tester,
          FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
          'wireframe_floating_action_button_unlabeled.json',
          {},
        );
      },
    );
  });

  group('WireframeGolden — images', () {
    testWidgets('Image without a semantic label emits a textless image shell', (
      tester,
    ) async {
      // No semantics label → text is null, but the image shell (role + bounds)
      // is still emitted as meaningful structure. RawImage with a synchronously
      // created ui.Image keeps the golden deterministic (no async decode).
      final testImage = await createColoredSquareImage(size: 80);
      await captureWireframeGolden(
        tester,
        SizedBox(width: 80, height: 80, child: RawImage(image: testImage)),
        'wireframe_image_unlabeled.json',
        {},
      );
    });

    testWidgets('Image falls back to its semanticLabel as the image text', (
      tester,
    ) async {
      // Mirrors the runtime structure Image(semanticLabel:) produces — the
      // label lives on an enclosing Semantics(image: true), not on RenderImage.
      // Unmasked → the label populates the image element's text.
      final testImage = await createColoredSquareImage(size: 80);
      await captureWireframeGolden(
        tester,
        Semantics(
          image: true,
          label: 'Company logo',
          child: SizedBox(
            width: 80,
            height: 80,
            child: RawImage(image: testImage),
          ),
        ),
        'wireframe_image_semantic_label.json',
        {},
      );
    });
  });

  group('WireframeGolden — nested directives', () {
    testWidgets(
      'MixpanelUnmask inside MixpanelMask is honored, then nulled geometrically',
      (tester) async {
        // Per the documented nesting behavior, the inner unmask IS honored —
        // it is not overridden by the enclosing mask context. But MixpanelMask
        // paints a container rect over its ENTIRE bounds and MaskPainter never
        // punches unmask regions back out of it (see the screenshot golden
        // `widget_explicitly_masked_with_inner_unmask.png`), so a non-
        // overflowing child is grayed in the image. The detector therefore
        // resolves `none` and Layer 2 strips the text: GEOMETRIC, not EXPLICIT.
        await captureWireframeGolden(
          tester,
          const MixpanelMask(
            child: MixpanelUnmask(child: Text('Nested Unmask')),
          ),
          'wireframe_nested_unmask_in_mask_geometric.json',
          {},
        );
      },
    );

    testWidgets(
      'MixpanelUnmask inside MixpanelMask below an intervening render object',
      (tester) async {
        // Same scenario, but the Column gives MixpanelMask a render object of
        // its own rather than resolving to the Text's RenderParagraph. Both
        // shapes must agree — this is what regressed when the marker element
        // collected its child's shared render object itself.
        await captureWireframeGolden(
          tester,
          const MixpanelMask(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MixpanelUnmask(child: Text('Nested Unmask')),
                Text('Masked Sibling'),
              ],
            ),
          ),
          'wireframe_nested_unmask_under_column_geometric.json',
          {},
        );
      },
    );

    testWidgets('MixpanelMask inside MixpanelUnmask emits child masked', (
      tester,
    ) async {
      // The inner mask wins on its own terms: the child resolves to EXPLICIT,
      // not an incidental geometric strip.
      await captureWireframeGolden(
        tester,
        const MixpanelUnmask(
          child: MixpanelMask(child: Text('Nested Mask Wins')),
        ),
        'wireframe_nested_mask_in_unmask.json',
        {},
      );
    });
  });

  group('WireframeGolden — geometric leak prevention', () {
    testWidgets(
      'Text visually overlapped by a MixpanelMask is nulled (geometric)',
      (tester) async {
        // A Positioned Text sits inside the same coordinate space as a
        // MixpanelMask-covered area, but is NOT a descendant of the mask.
        // The mask-detector walk marks it as MaskDecision.none, then the
        // emitter's geometric-masking stage catches the overlap.
        await captureWireframeGolden(
          tester,
          SizedBox(
            width: 300,
            height: 200,
            child: Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 20,
                  child: MixpanelMask(
                    child: Container(
                      width: 260,
                      height: 160,
                      color: Colors.red.shade100,
                    ),
                  ),
                ),
                const Positioned(left: 40, top: 80, child: Text('Leaked?')),
              ],
            ),
          ),
          'wireframe_geometric_overlap_nulled.json',
          {},
        );
      },
    );
  });

  group('WireframeGolden — user sensitive rules', () {
    testWidgets('StripRule nulls text on substring match', (tester) async {
      await captureWireframeGolden(
        tester,
        const Text('Bearer eyJhbGciOi'),
        'wireframe_rule_strip.json',
        {},
        sensitiveRules: const [StripRule('Bearer ')],
      );
    });

    testWidgets('RedactRule rewrites matches in place', (tester) async {
      await captureWireframeGolden(
        tester,
        const Text('email: alice@example.com'),
        'wireframe_rule_redact.json',
        {},
        sensitiveRules: const [
          RedactRule('alice@example.com', replacement: '[EMAIL]'),
        ],
      );
    });

    testWidgets('StripRegexRule nulls text on regex match', (tester) async {
      await captureWireframeGolden(
        tester,
        const Text('token-abc123'),
        'wireframe_rule_strip_regex.json',
        {},
        sensitiveRules: [StripRegexRule(RegExp(r'^token-'))],
      );
    });

    testWidgets('RedactRegexRule rewrites regex matches in place', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        const Text('SSN: 123-45-6789'),
        'wireframe_rule_redact_regex.json',
        {},
        sensitiveRules: [
          RedactRegexRule(RegExp(r'\d{3}-\d{2}-\d{4}'), replacement: '[SSN]'),
        ],
      );
    });
  });

  group('WireframeGolden — complex mixed masking', () {
    testWidgets(
      'mirrors the Complex view mask golden — same widget tree, wireframe view',
      (tester) async {
        // Widget tree intentionally identical to the "Complex view with
        // mixed masking" test in masking_golden_test.dart. Comparing the
        // resulting wireframe overlay against complex_mixed_masking.png
        // validates that the wireframe bounds line up with the rendered
        // pixels for a realistic multi-widget layout.
        final testImage = await createColoredSquareImage(
          size: 40,
          color: Colors.orange,
        );

        await captureWireframeGolden(
          tester,
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Auto-masked text'),
              const SizedBox(height: 8),
              RawImage(image: testImage),
              const SizedBox(height: 8),
              const MixpanelUnmask(child: Text('Explicitly unmasked')),
              const SizedBox(height: 8),
              MixpanelMask(child: RawImage(image: testImage)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Left'),
                  const SizedBox(width: 8),
                  RawImage(image: testImage),
                  const SizedBox(width: 8),
                  const MixpanelUnmask(child: Text('Middle')),
                  const SizedBox(width: 8),
                  const MixpanelMask(child: Text('Masked')),
                  const SizedBox(width: 8),
                  const Text('Right'),
                ],
              ),
            ],
          ),
          'wireframe_complex_mixed_masking.json',
          {AutoMaskedView.text},
          width: 400,
          height: 350,
        );
      },
    );
  });

  group('WireframeGolden — declared wireframe text', () {
    testWidgets(
      'MixpanelMask(wireframeText:) survives masking on the direct child',
      (tester) async {
        // Declared text is orthogonal to masking: the pixels are grayed but the
        // authored label is emitted on the direct child (the image here) with
        // MaskDecision.declared. It rides the child's real role + bounds,
        // so the RawImage must be the DIRECT child to classify as role image (a
        // SizedBox wrapper would classify as role text).
        final testImage = await createColoredSquareImage(size: 80);
        await captureWireframeGolden(
          tester,
          MixpanelMask(
            wireframeText: 'profile photo',
            child: RawImage(image: testImage, width: 80, height: 80),
          ),
          'wireframe_declared_mask_image.json',
          {},
        );
      },
    );

    testWidgets('MixpanelUnmask(wireframeText:) labels custom-drawn content', (
      tester,
    ) async {
      // CustomPaint has no scrapeable text; the declared label describes it.
      // Not a button, not an image → role text.
      await captureWireframeGolden(
        tester,
        const MixpanelUnmask(
          wireframeText: 'monthly spend',
          child: SizedBox(width: 120, height: 60, child: Placeholder()),
        ),
        'wireframe_declared_unmask_custom.json',
        {},
      );
    });

    testWidgets('declared text on a button child adopts the button role', (
      tester,
    ) async {
      // The declared text replaces the scraped "Submit" label and the element
      // is classified against the button child (role button), not the marker.
      await captureWireframeGolden(
        tester,
        MixpanelMask(
          wireframeText: 'checkout action',
          child: ElevatedButton(onPressed: () {}, child: const Text('Submit')),
        ),
        'wireframe_declared_button.json',
        {},
      );
    });

    testWidgets('declared text labels a TextField without leaking its value', (
      tester,
    ) async {
      // The ERD's own example: an editable field emits the authored label as
      // role input. Declared text REPLACES scraped text, so the typed value
      // still never ships — labeling the field costs nothing in privacy.
      await captureWireframeGolden(
        tester,
        MixpanelMask(
          wireframeText: 'Card number',
          child: TextField(
            controller: TextEditingController(text: '4111111111111111'),
          ),
        ),
        'wireframe_declared_textfield.json',
        {},
      );
    });

    testWidgets('declared text labels a CupertinoTextField as role input', (
      tester,
    ) async {
      // Different internal tree from the Material field, same contract.
      await captureWireframeGolden(
        tester,
        MixpanelUnmask(
          wireframeText: 'Search',
          child: CupertinoTextField(
            controller: TextEditingController(text: 'secret-query'),
          ),
        ),
        'wireframe_declared_cupertino_textfield.json',
        {},
      );
    });

    testWidgets('a labeled container does not absorb the field inside it', (
      tester,
    ) async {
      // The label lands on the container, which is not itself a field, so it
      // stays role text and the TextField still emits its own textless input —
      // matching Android, where the EditText emits separately from the
      // container that carries the declared text.
      await captureWireframeGolden(
        tester,
        MixpanelUnmask(
          wireframeText: 'payment form',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Pay now'),
              TextField(controller: TextEditingController(text: '4111')),
            ],
          ),
        ),
        'wireframe_declared_container_keeps_input.json',
        {},
      );
    });

    testWidgets('declared text still runs through SensitiveRules', (
      tester,
    ) async {
      // Layer 4 safety net: a StripRule matching the authored label nulls it.
      await captureWireframeGolden(
        tester,
        const MixpanelUnmask(
          wireframeText: 'card 4111 secret',
          child: Text('anything'),
        ),
        'wireframe_declared_rule_stripped.json',
        {},
        sensitiveRules: const [StripRule('secret')],
      );
    });
  });

  group('WireframeGolden — accessibility label fallback disabled', () {
    testWidgets('icon-only button drops its label and ships a bare shell', (
      tester,
    ) async {
      // With the fallback off, the tooltip is never read: the button is still
      // emitted (structure is not content) but carries no text.
      await captureWireframeGolden(
        tester,
        IconButton(
          onPressed: () {},
          tooltip: 'Open settings',
          icon: const Icon(Icons.settings),
        ),
        'wireframe_button_label_fallback_off.json',
        {},
        useAccessibilityLabelFallback: false,
      );
    });

    testWidgets('visible button text is unaffected by the flag', (
      tester,
    ) async {
      // The flag gates the FALLBACK only — text scraped off the screen still
      // ships, because it is already visible in the unmasked screenshot.
      await captureWireframeGolden(
        tester,
        ElevatedButton(onPressed: () {}, child: const Text('Continue')),
        'wireframe_button_label_fallback_off_with_text.json',
        {},
        useAccessibilityLabelFallback: false,
      );
    });

    testWidgets('image drops its semanticLabel and ships a bare shell', (
      tester,
    ) async {
      final testImage = await createColoredSquareImage(size: 80);
      await captureWireframeGolden(
        tester,
        Semantics(
          image: true,
          label: 'Company logo',
          child: SizedBox(
            width: 80,
            height: 80,
            child: RawImage(image: testImage),
          ),
        ),
        'wireframe_image_label_fallback_off.json',
        {},
        useAccessibilityLabelFallback: false,
      );
    });

    testWidgets('declared text still ships with the fallback off', (
      tester,
    ) async {
      // wireframeText is authored, not a scraped label, so the flag has no
      // bearing on it — it stays the one way to describe an icon-only button.
      await captureWireframeGolden(
        tester,
        MixpanelUnmask(
          wireframeText: 'Open settings',
          child: IconButton(
            onPressed: () {},
            tooltip: 'Open settings',
            icon: const Icon(Icons.settings),
          ),
        ),
        'wireframe_declared_beats_label_fallback_off.json',
        {},
        useAccessibilityLabelFallback: false,
      );
    });
  });

  group('WireframeGolden — truncation', () {
    testWidgets('over-length text is truncated with ellipsis', (tester) async {
      const longText =
          'This is a long piece of text that should exceed the cap '
          'and therefore trigger truncation';
      await captureWireframeGolden(
        tester,
        const Text(longText),
        'wireframe_text_truncated.json',
        {},
      );
    });
  });
}
