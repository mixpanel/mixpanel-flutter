// Legacy Radio constructor keeps these fixtures compatible with Flutter 3.19.
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/response_snapshot.dart';

class TestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(TestPainter oldDelegate) => false;
}

void main() {
  Future<ResponseSnapshot?> capture(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    return ResponseSnapshot.capture(tester.element(find.byType(MaterialApp)),
        const Rect.fromLTWH(0, 0, 800, 600));
  }

  testWidgets('equal content stays equal; same-sized text changes differ',
      (tester) async {
    final first = await capture(tester, const Text('AAAA'));
    final same = await capture(tester, const Text('AAAA'));
    final changed = await capture(tester, const Text('BBBB'));
    expect(first, isNotNull);
    expect(first!.differsFrom(same!), isFalse);
    expect(first.differsFrom(changed!), isTrue);
  });
  testWidgets('transform changes contribute logical geometry', (tester) async {
    final first = await capture(
        tester,
        Transform.translate(
            offset: const Offset(10, 20), child: const Text('text')));
    final same = await capture(
        tester,
        Transform.translate(
            offset: const Offset(10, 20), child: const Text('text')));
    final moved = await capture(
        tester,
        Transform.translate(
            offset: const Offset(30, 20), child: const Text('text')));
    expect(first, isNotNull);
    expect(first!.differsFrom(same!), isFalse);
    expect(first.differsFrom(moved!), isTrue);
  });
  testWidgets(
      'visible custom painter is unknown; proven offscreen painter is supported',
      (tester) async {
    Widget painted(double x) => Transform.translate(
        offset: Offset(x, 0),
        child: CustomPaint(painter: TestPainter(), size: const Size(20, 20)));
    expect(await capture(tester, painted(0)), isNull);
    expect(await capture(tester, painted(1000)), isNotNull);
  });
  testWidgets(
      'Material internal paint supported; application child paint unknown',
      (tester) async {
    expect(
        await capture(tester,
            ElevatedButton(onPressed: () {}, child: const Text('button'))),
        isNotNull);
    expect(
        await capture(
            tester,
            Material(
                child: CustomPaint(
                    painter: TestPainter(), size: const Size(20, 20)))),
        isNull);
  });
  testWidgets('editable values do not change response digest', (tester) async {
    final controller = TextEditingController(text: 'first secret');
    final first = await capture(tester, TextField(controller: controller));
    controller.text = 'second secret';
    await tester.pump();
    final second = ResponseSnapshot.capture(
        tester.element(find.byType(MaterialApp)),
        const Rect.fromLTWH(0, 0, 800, 600));
    expect(first, isNotNull);
    expect(first!.differsFrom(second!), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets('radio selected state changes response', (tester) async {
    final first = await capture(
        tester, Radio<int>(value: 1, groupValue: 0, onChanged: (_) {}));
    final second = await capture(
        tester, Radio<int>(value: 1, groupValue: 1, onChanged: (_) {}));
    expect(first, isNotNull);
    expect(first!.differsFrom(second!), isTrue);
  });
  testWidgets('budget exhaustion and empty viewport are unknown',
      (tester) async {
    expect(
        await capture(
            tester,
            Column(
                children: List.generate(2100, (_) => const SizedBox.shrink()))),
        isNull);
    expect(
        ResponseSnapshot.capture(
            tester.element(find.byType(MaterialApp)), Rect.zero),
        isNull);
  });
  for (final offscreen in [false, true]) {
    testWidgets('platform texture visibility: offscreen=$offscreen',
        (tester) async {
      final result = await capture(
          tester,
          Transform.translate(
              offset: Offset(offscreen ? 1000 : 0, 0),
              child: const SizedBox(
                  width: 20, height: 20, child: Texture(textureId: 123))));
      expect(result, offscreen ? isNotNull : isNull);
    });
  }

  for (final offscreen in [false, true]) {
    testWidgets('stateful platform view geometry: offscreen=$offscreen',
        (tester) async {
      final result = await capture(
          tester,
          Transform.translate(
              offset: Offset(offscreen ? 1000 : 0, 0),
              child: const GeometryOnlyAndroidView()));
      expect(result, offscreen ? isNotNull : isNull);
    });
  }

  testWidgets('portal response remains visible through zero-sized host',
      (tester) async {
    final portal = OverlayPortalController();
    var text = 'AAAA';
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
      update = setState;
      return OverlayPortal(
          controller: portal,
          overlayChildBuilder: (_) =>
              Positioned(left: 20, top: 20, child: Text(text)),
          child: const SizedBox.shrink());
    }))));
    portal.show();
    await tester.pump();
    ResponseSnapshot? snapshot() => ResponseSnapshot.capture(
        tester.element(find.byType(MaterialApp)),
        const Rect.fromLTWH(0, 0, 800, 600));
    final first = snapshot();
    update(() => text = 'BBBB');
    await tester.pump();
    expect(first, isNotNull);
    expect(first!.differsFrom(snapshot()!), isTrue);
  });
}

// Exercise StatefulElement render lookup without creating a native platform view.
class GeometryOnlyAndroidView extends AndroidView {
  const GeometryOnlyAndroidView({super.key}) : super(viewType: 'geometry-test');
  @override
  State<AndroidView> createState() => GeometryOnlyAndroidViewState();
}

class GeometryOnlyAndroidViewState extends State<AndroidView> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20);
}
