@Tags(['golden'])
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/widgets.dart';

import 'utils/golden_test_utils.dart';

void main() {
  testWidgets('Text masked', (tester) async {
    await captureGolden(
      tester,
      const Text('Sensitive Information'),
      'text_masked.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('Text unmasked', (tester) async {
    await captureGolden(
      tester,
      const Text('Public Information'),
      'text_unmasked.png',
      {},
    );
  });

  testWidgets('TextField masked', (tester) async {
    await captureGolden(
      tester,
      TextField(controller: TextEditingController(text: 'test@example.com')),
      'textfield_masked.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('TextField always masked (security - auto-mask disabled)', (
    tester,
  ) async {
    await captureGolden(
      tester,
      TextField(controller: TextEditingController(text: 'visible@example.com')),
      'textfield_masked_with_auto_mask_disabled.png', // Same golden file, but now shows masked
      {}, // Auto-masking disabled, but TextField is still masked for security
    );
  });

  testWidgets(
    'TextField in MixpanelUnmask is still masked (security override)',
    (tester) async {
      await captureGolden(
        tester,
        MixpanelUnmask(
          child: TextField(
            controller: TextEditingController(text: 'password123'),
          ),
        ),
        'textfield_in_unmask_still_masked.png',
        {AutoMaskedView.text}, // Even with auto-masking enabled
      );
    },
  );

  testWidgets('CupertinoTextField masked', (tester) async {
    await captureGolden(
      tester,
      CupertinoTextField(controller: TextEditingController(text: 'secret123')),
      'cupertino_textfield_masked_with_auto_mask.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('CupertinoTextField always masked (security - auto-mask disabled)', (
    tester,
  ) async {
    await captureGolden(
      tester,
      CupertinoTextField(
        controller: TextEditingController(text: 'public text'),
      ),
      'cupertino_masked_with_auto_mask_disabled.png', // Same golden file, but now shows masked
      {}, // Auto-masking disabled, but CupertinoTextField is still masked for security
    );
  });

  testWidgets(
    'CupertinoTextField in MixpanelUnmask is still masked (security)',
    (tester) async {
      await captureGolden(
        tester,
        MixpanelUnmask(
          child: CupertinoTextField(
            controller: TextEditingController(text: 'sensitive-input'),
          ),
        ),
        'cupertino_textfield_in_unmask_still_masked.png',
        {AutoMaskedView.text},
      );
    },
  );

  testWidgets('TextField masked in nested Unmask', (tester) async {
    await captureGolden(
      tester,
      MixpanelUnmask(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Public label text'),
            const SizedBox(height: 8),
            TextField(controller: TextEditingController(text: 'password')),
          ],
        ),
      ),
      'mixed_unmask_text_unmasked_textfield_masked.png',
      {AutoMaskedView.text},
      width: 300,
      height: 200,
    );
  });

  testWidgets('Icon masked', (tester) async {
    await captureGolden(tester, const Icon(Icons.person), 'icon_masked.png', {
      AutoMaskedView.text,
    });
  });

  testWidgets('Icon unmasked', (tester) async {
    await captureGolden(
      tester,
      const Icon(Icons.person),
      'icon_unmasked.png',
      {},
    );
  });

  testWidgets('ElevatedButton masked', (tester) async {
    await captureGolden(
      tester,
      ElevatedButton(onPressed: () {}, child: const Text('Submit')),
      'elevated_button_masked.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('ElevatedButton unmasked', (tester) async {
    await captureGolden(
      tester,
      ElevatedButton(onPressed: () {}, child: const Text('Submit')),
      'elevated_button_unmasked.png',
      {},
    );
  });

  testWidgets('TextButton masked', (tester) async {
    await captureGolden(
      tester,
      TextButton(onPressed: () {}, child: const Text('Cancel')),
      'text_button_masked.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('TextButton unmasked', (tester) async {
    await captureGolden(
      tester,
      TextButton(onPressed: () {}, child: const Text('Cancel')),
      'text_button_unmasked.png',
      {},
    );
  });

  testWidgets('CupertinoButton masked', (tester) async {
    await captureGolden(
      tester,
      CupertinoButton(onPressed: () {}, child: const Text('Action')),
      'cupertino_button_masked.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('CupertinoButton unmasked', (tester) async {
    await captureGolden(
      tester,
      CupertinoButton(onPressed: () {}, child: const Text('Action')),
      'cupertino_button_unmasked.png',
      {},
    );
  });

  testWidgets('Widget explicitly unmasked', (tester) async {
    await captureGolden(
      tester,
      const MixpanelUnmask(child: Text('Public Information')),
      'widet_explicitly_unmasked.png',
      {AutoMaskedView.text},
    );
  });

  testWidgets('Widget explicitly masked', (tester) async {
    await captureGolden(
      tester,
      const MixpanelMask(child: Text('Sensitive Information')),
      'widget_explicitly_masked.png',
      {},
    );
  });

  testWidgets(
    'MixpanelMask container rect covers inner MixpanelUnmask within bounds',
    (tester) async {
      await captureGolden(
        tester,
        const MixpanelMask(
          child: FittedBox(
            child: MixpanelUnmask(child: Text('Sensitive Information')),
          ),
        ),
        'widget_explicitly_masked_with_inner_unmask.png',
        {},
      );
    },
  );

  testWidgets('Widget explicitly unmasked allows inner masking', (
    tester,
  ) async {
    await captureGolden(
      tester,
      const MixpanelUnmask(
        child: FittedBox(
          child: MixpanelMask(child: Text('Public Information')),
        ),
      ),
      'widget_explicitly_unmasked_with_inner_mask.png',
      {},
    );
  });

  testWidgets('Image masked with auto-masking', (tester) async {
    final image = await createColoredSquareImage(size: 60, color: Colors.blue);
    await captureGolden(tester, RawImage(image: image), 'image_masked.png', {
      AutoMaskedView.image,
    });
  });

  testWidgets('Image unmasked without auto-masking', (tester) async {
    final image = await createColoredSquareImage(size: 60, color: Colors.green);
    await captureGolden(
      tester,
      RawImage(image: image),
      'image_unmasked.png',
      {},
    );
  });

  testWidgets('Image explicitly masked', (tester) async {
    final image = await createColoredSquareImage(size: 60, color: Colors.red);
    await captureGolden(
      tester,
      MixpanelMask(child: RawImage(image: image)),
      'image_explicitly_masked.png',
      {},
    );
  });

  testWidgets('Image explicitly unmasked', (tester) async {
    final image = await createColoredSquareImage(
      size: 60,
      color: Colors.purple,
    );
    await captureGolden(
      tester,
      MixpanelUnmask(child: RawImage(image: image)),
      'image_explicitly_unmasked.png',
      {AutoMaskedView.image},
    );
  });

  testWidgets('Complex view with mixed masking', (tester) async {
    final testImage = await createColoredSquareImage(
      size: 40,
      color: Colors.orange,
    );

    await captureGolden(
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
      'complex_mixed_masking.png',
      {AutoMaskedView.text},
      width: 400,
      height: 350,
    );
  });

  testWidgets('ListView with text masked', (tester) async {
    await captureGolden(
      tester,
      ListView(
        children: const [
          Padding(padding: EdgeInsets.all(8.0), child: Text('ListView item 1')),
          Padding(padding: EdgeInsets.all(8.0), child: Text('ListView item 2')),
          Padding(padding: EdgeInsets.all(8.0), child: Text('ListView item 3')),
        ],
      ),
      'listview_text_masked.png',
      {AutoMaskedView.text},
      width: 250,
      height: 150,
    );
  });

  testWidgets('SingleChildScrollView with text masked', (tester) async {
    await captureGolden(
      tester,
      SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Scrollable text 1'),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Scrollable text 2'),
            ),
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Scrollable text 3'),
            ),
          ],
        ),
      ),
      'scrollview_text_masked.png',
      {AutoMaskedView.text},
      width: 250,
      height: 150,
    );
  });

  testWidgets('ListView with mixed content masked', (tester) async {
    final testImage = await createColoredSquareImage(
      size: 40,
      color: Colors.blue,
    );

    await captureGolden(
      tester,
      ListView(
        children: [
          const Padding(padding: EdgeInsets.all(8.0), child: Text('Text item')),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: RawImage(image: testImage),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Another text item'),
          ),
        ],
      ),
      'listview_mixed_content_masked.png',
      {AutoMaskedView.text, AutoMaskedView.image},
      width: 250,
      height: 200,
    );
  });

  // ── Masking standard illustration tests ──────────────────────────────
  // These tests generate golden images used in the masking standard
  // document (reference/masking-proposals/README.md).

  testWidgets('MixpanelMask masks container with mixed children', (
    tester,
  ) async {
    final image = await createColoredSquareImage(size: 40, color: Colors.blue);
    await captureGolden(
      tester,
      MixpanelMask(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Name: Tyler'),
            const SizedBox(height: 8),
            SizedBox(width: 40, height: 40, child: RawImage(image: image)),
            const SizedBox(height: 8),
            SizedBox(
              width: 200,
              child: TextField(
                controller: TextEditingController(text: 'tyler@example.com'),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ),
          ],
        ),
      ),
      'mask_container_mixed_children.png',
      {},
      width: 300,
      height: 250,
    );
  });

  testWidgets('MixpanelUnmask with mixed children overrides auto-masking', (
    tester,
  ) async {
    final image = await createColoredSquareImage(size: 40, color: Colors.blue);
    await captureGolden(
      tester,
      MixpanelUnmask(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Public label'),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: RawImage(image: image),
                  ),
                  const SizedBox(width: 8),
                  const Text('Visible caption'),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: TextEditingController(text: 'password123'),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
              ),
            ],
          ),
        ),
      ),
      'unmask_container_mixed_children.png',
      {AutoMaskedView.image},
      width: 300,
      height: 250,
    );
  });

  testWidgets('MixpanelMask with inner MixpanelUnmask', (tester) async {
    await captureGolden(
      tester,
      MixpanelMask(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Padding(padding: EdgeInsets.all(8), child: Text('Header (masked)')),
            MixpanelUnmask(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text('Public note (unmask inside mask)'),
              ),
            ),
            Padding(padding: EdgeInsets.all(8), child: Text('Footer (masked)')),
          ],
        ),
      ),
      'mask_with_inner_unmask.png',
      {},
      width: 300,
      height: 150,
    );
  });

  testWidgets('MixpanelUnmask with inner MixpanelMask', (tester) async {
    await captureGolden(
      tester,
      MixpanelUnmask(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('Public (visible)'),
            ),
            MixpanelMask(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text('Private (masked)'),
              ),
            ),
          ],
        ),
      ),
      'unmask_with_inner_mask.png',
      {AutoMaskedView.text},
      width: 300,
      height: 120,
    );
  });

  testWidgets('Deeply nested mask and unmask directives', (tester) async {
    await captureGolden(
      tester,
      MixpanelMask(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Padding(padding: EdgeInsets.all(8), child: Text('Masked A')),
            MixpanelUnmask(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 24, top: 8, bottom: 8),
                    child: Text('Visible B (unmask)'),
                  ),
                  MixpanelMask(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 48, top: 8, bottom: 8),
                          child: Text('Masked C'),
                        ),
                        MixpanelUnmask(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 72,
                              top: 8,
                              bottom: 8,
                            ),
                            child: Text('Visible D (unmask)'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      'deeply_nested_mask_unmask.png',
      {},
      width: 350,
      height: 220,
    );
  });

  testWidgets('Auto-masking without explicit directives', (tester) async {
    final image = await createColoredSquareImage(size: 40, color: Colors.green);
    await captureGolden(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Hello World'),
          const SizedBox(height: 8),
          SizedBox(width: 40, height: 40, child: RawImage(image: image)),
          const SizedBox(height: 8),
          SizedBox(
            width: 200,
            child: TextField(
              controller: TextEditingController(text: 'search query'),
              decoration: const InputDecoration(labelText: 'Search'),
            ),
          ),
        ],
      ),
      'auto_masking_no_directive.png',
      {AutoMaskedView.image},
      width: 300,
      height: 250,
    );
  });

  testWidgets('MixpanelMask overflow children are individually masked', (
    tester,
  ) async {
    await captureGolden(
      tester,
      MixpanelMask(
        child: SizedBox(
          width: 150,
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(color: Colors.blue),
              Positioned(
                right: -120,
                top: 15,
                child: Container(
                  width: 130,
                  height: 50,
                  color: Colors.red,
                  alignment: Alignment.center,
                  child: const Text(
                    'Outside',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      'mask_overflow_children.png',
      {},
      width: 380,
      height: 150,
    );
  });

  testWidgets('MixpanelUnmask overflow escapes MixpanelMask bounds', (
    tester,
  ) async {
    await captureGolden(
      tester,
      MixpanelMask(
        child: SizedBox(
          width: 150,
          height: 80,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(color: Colors.blue),
              const MixpanelUnmask(
                child: Positioned(
                  right: -120,
                  top: 15,
                  child: SizedBox(
                    width: 130,
                    height: 50,
                    child: ColoredBox(
                      color: Colors.green,
                      child: Center(child: Text('Unmasked')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      'unmask_overflow_escapes_mask.png',
      {},
      width: 380,
      height: 150,
    );
  });

  testWidgets('TextField security override inside MixpanelUnmask', (
    tester,
  ) async {
    await captureGolden(
      tester,
      MixpanelUnmask(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('Username')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 250,
                child: TextField(
                  controller: TextEditingController(text: 'tyler@example.com'),
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.all(8), child: Text('Password')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 250,
                child: TextField(
                  controller: TextEditingController(text: 'secret123'),
                  obscureText: true,
                ),
              ),
            ),
          ],
        ),
      ),
      'textfield_security_in_unmask.png',
      {AutoMaskedView.text},
      width: 300,
      height: 250,
    );
  });
}
