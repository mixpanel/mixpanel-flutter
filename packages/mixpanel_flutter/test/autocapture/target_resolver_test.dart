import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/target_resolver.dart';

void main() {
  final resolver = TargetResolver();
  Future<CaptureTarget?> resolve(WidgetTester tester, Widget child) async {
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
    final position = tester.getCenter(find.text('private text'));
    return resolver.resolve(tester.element(find.byType(MaterialApp)),
        PointerDownEvent(position: position));
  }

  testWidgets(
      'button owner identifier excludes descendant labels, IDs and keys',
      (tester) async {
    final target = await resolve(
        tester,
        Semantics(
            identifier: 'owner',
            child: ElevatedButton(
                onPressed: () {},
                child: Semantics(
                    identifier: 'descendant',
                    label: 'secret label',
                    child: const Text('private text',
                        key: ValueKey('secret key'))))));
    expect(target, isNotNull);
    expect(target!.event.elementId, 'owner');
    expect(target.event.tagName, 'ElevatedButton');
    expect(target.deadEligible, isTrue);
    expect('${target.event.elementId} ${target.event.elements}',
        isNot(contains('secret')));
  });

  testWidgets('structural IDs ignore text labels and invalid explicit IDs',
      (tester) async {
    Future<CaptureTarget?> capture(String id, String label) => resolve(
        tester,
        Semantics(
            identifier: id,
            label: label,
            child: ElevatedButton(
                onPressed: () {}, child: const Text('private text'))));
    final first = await capture(' ', 'one private label');
    final second =
        await capture(List.filled(257, 'x').join(), 'another private label');
    expect(first, isNotNull);
    expect(second!.event.elementId, first!.event.elementId);
    expect(first.event.elementId, startsWith('ElevatedButton_'));
    expect(first.event.elementId, isNot(contains('private')));
  });

  testWidgets('nested actionable child keeps its own identity', (tester) async {
    final target = await resolve(
        tester,
        Semantics(
            identifier: 'outer',
            child: ElevatedButton(
                onPressed: () {},
                child: Semantics(
                    identifier: 'inner',
                    child: GestureDetector(
                        onTap: () {}, child: const Text('private text'))))));
    expect(target!.event.elementId, 'inner');
    expect(target.event.tagName, 'GestureDetector');
  });

  testWidgets('identifier outside ancestor cap is ignored', (tester) async {
    Widget child =
        GestureDetector(onTap: () {}, child: const Text('private text'));
    for (var i = 0; i < 12; i++) {
      child = Padding(padding: EdgeInsets.zero, child: child);
    }
    final target =
        await resolve(tester, Semantics(identifier: 'too-far', child: child));
    expect(target, isNotNull);
    expect(target!.event.elementId, isNot('too-far'));
  });

  testWidgets('disabled button and noninteractive text are not dead eligible',
      (tester) async {
    final disabled = await resolve(tester,
        const ElevatedButton(onPressed: null, child: Text('private text')));
    expect(disabled!.deadEligible, isFalse);
    final text = await resolve(tester, const Text('private text'));
    expect(text!.deadEligible, isFalse);
  });

  testWidgets('zero-sized portal resolves visible overlay owner directly',
      (tester) async {
    final portal = OverlayPortalController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OverlayPortal(
                controller: portal,
                overlayChildBuilder: (_) => Center(
                    child: Semantics(
                        identifier: 'portal',
                        child: ElevatedButton(
                            onPressed: () {},
                            child: const Text('private text')))),
                child: const SizedBox.shrink()))));
    portal.show();
    await tester.pump();
    final target = resolver.resolve(
        tester.element(find.byType(MaterialApp)),
        PointerDownEvent(
            position: tester.getCenter(find.text('private text'))));
    expect(target!.event.elementId, 'portal');
    expect(target.deadEligible, isTrue);
  });
  testWidgets('portal fallback budget exhaustion returns no fabricated target',
      (tester) async {
    final portal = OverlayPortalController();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      IgnorePointer(
          child: Column(
              children: List.generate(2500, (_) => const SizedBox.shrink()))),
      OverlayPortal(
          controller: portal,
          overlayChildBuilder: (_) => Center(
              child: ElevatedButton(
                  onPressed: () {}, child: const Text('private text'))),
          child: const SizedBox.shrink()),
    ]))));
    portal.show();
    await tester.pump();
    expect(
        resolver.resolve(
            tester.element(find.byType(MaterialApp)),
            PointerDownEvent(
                position: tester.getCenter(find.text('private text')))),
        isNull);
  });
}
