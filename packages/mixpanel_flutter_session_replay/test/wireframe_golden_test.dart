@Tags(['golden'])
library;

import 'dart:typed_data';

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

    testWidgets('IconButton without a label is dropped as noise', (
      tester,
    ) async {
      // The icon renders as a Material Icons private-use codepoint, which
      // carries no useful text for the AI. Noise-drop removes it entirely.
      await captureWireframeGolden(
        tester,
        IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
        'wireframe_icon_button_dropped.json',
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

    testWidgets('FloatingActionButton with only an icon is dropped as noise', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
        'wireframe_floating_action_button_dropped.json',
        {},
      );
    });
  });

  group('WireframeGolden — images', () {
    testWidgets('Image without a semantic label is dropped as noise', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        SizedBox(
          width: 80,
          height: 80,
          child: Image(image: MemoryImage(_transparentPng)),
        ),
        'wireframe_image_unlabeled_dropped.json',
        {},
      );
    });
  });

  group('WireframeGolden — nested directives', () {
    testWidgets('MixpanelUnmask inside MixpanelMask emits child unmasked', (
      tester,
    ) async {
      await captureWireframeGolden(
        tester,
        const MixpanelMask(
          child: MixpanelUnmask(child: Text('Nested Unmask Wins')),
        ),
        'wireframe_nested_unmask_in_mask.json',
        {},
      );
    });

    testWidgets('MixpanelMask inside MixpanelUnmask emits child masked', (
      tester,
    ) async {
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

  group('WireframeGolden — truncation', () {
    testWidgets('text longer than 60 chars is truncated with ellipsis', (
      tester,
    ) async {
      const longText =
          'This is a long piece of text that should exceed sixty '
          'characters and therefore trigger truncation';
      await captureWireframeGolden(
        tester,
        const Text(longText),
        'wireframe_text_truncated.json',
        {},
      );
    });
  });
}

/// 1x1 transparent PNG used to test Image widget wireframing without
/// depending on real asset loading.
final _transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, //
  0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, //
  0x42, 0x60, 0x82,
]);
