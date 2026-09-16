import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/wireframe.dart';

void main() {
  Future<List<WireframeElement>> collect(
    WidgetTester tester,
    Widget widget,
  ) async {
    const boundaryKey = ValueKey('capture-boundary');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(key: boundaryKey, child: widget),
        ),
      ),
    );
    await tester.pump();

    final boundaryElement = tester.element(find.byKey(boundaryKey));
    final boundary = boundaryElement.renderObject! as RenderRepaintBoundary;
    return MaskDetector(
          directive: MaskingDirective(autoMaskTypes: const {}),
          collectWireframes: true,
        )
        .detectMaskRegions(boundary, boundaryElement: boundaryElement)
        .rawWireframes!;
  }

  testWidgets('should detect a customer widget when its name ends in Button', (
    tester,
  ) async {
    final elements = await collect(tester, const CheckoutButton());

    expect(elements, hasLength(1));
    expect(elements.single.role, WireframeRole.button);
    expect(elements.single.text, 'Checkout');
  });

  testWidgets(
    'should detect a generic widget when its base name ends in Button',
    (tester) async {
      final elements = await collect(tester, const GenericButton<String>());

      expect(elements, hasLength(1));
      expect(elements.single.role, WireframeRole.button);
      expect(elements.single.text, 'Generic');
    },
  );

  testWidgets('should not detect a widget when Button is not the name suffix', (
    tester,
  ) async {
    final elements = await collect(tester, const ButtonContainer());

    expect(
      elements.where((element) => element.role == WireframeRole.button),
      isEmpty,
    );
    expect(elements.single.role, WireframeRole.text);
    expect(elements.single.text, 'Container');
  });
}

class CheckoutButton extends StatelessWidget {
  const CheckoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 100,
      height: 40,
      child: Center(child: Text('Checkout')),
    );
  }
}

class GenericButton<T> extends StatelessWidget {
  const GenericButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 100,
      height: 40,
      child: Center(child: Text('Generic')),
    );
  }
}

class ButtonContainer extends StatelessWidget {
  const ButtonContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Text('Container');
  }
}
