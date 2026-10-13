import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/src/autocapture/autocapture_options.dart';
import 'package:mixpanel_flutter/src/autocapture/capture_session.dart';
import 'package:mixpanel_flutter/src/autocapture/click_event.dart';
import 'package:mixpanel_flutter/src/autocapture/response_snapshot.dart';

void main() {
  const unchanged = ResponseSnapshot(1);
  late List<String> emitted;
  late Offset center;
  var pointer = 0;
  var time = Duration.zero;

  Future<CaptureSession> session(WidgetTester tester,
      [AutocaptureOptions options = const AutocaptureOptions()]) async {
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: Semantics(
                identifier: 'checkout',
                child: ElevatedButton(
                    onPressed: () {}, child: const Text('Buy'))))));
    center = tester.getCenter(find.text('Buy'));
    emitted = [];
    return CaptureSession(options,
        root: tester.element(find.byType(Directionality)),
        capture: () => unchanged,
        emit: (name, ClickEvent event) =>
            emitted.add('$name:${event.elementId}'));
  }

  PointerDownEvent down() {
    time += const Duration(milliseconds: 100);
    return PointerDownEvent(
        pointer: ++pointer, position: center, timeStamp: time);
  }

  PointerUpEvent up() => PointerUpEvent(
      pointer: pointer,
      position: center,
      timeStamp: time + const Duration(milliseconds: 40));

  void tap(CaptureSession s) {
    s.down(down(), 18);
    s.up(up());
  }

  testWidgets('accepted taps emit click, rage and dead events', (tester) async {
    final s = await session(tester);
    for (var i = 0; i < 4; i++) {
      tap(s);
    }
    await tester.pump(const Duration(milliseconds: 501));
    expect(emitted, [
      for (var i = 0; i < 4; i++) r'$mp_click:checkout',
      r'$mp_rage_click:checkout',
      r'$mp_dead_click:checkout',
    ]);
  });

  testWidgets('a response during the press drops the dead check',
      (tester) async {
    final s = await session(tester);
    s.down(down(), 18);
    s.onResponse();
    s.up(up());
    await tester.pump(const Duration(milliseconds: 501));
    expect(emitted, [r'$mp_click:checkout']);
  });

  testWidgets('cancelPendingCheck stops an armed dead check', (tester) async {
    final s = await session(tester);
    tap(s);
    s.cancelPendingCheck();
    await tester.pump(const Duration(milliseconds: 501));
    expect(emitted, [r'$mp_click:checkout']);
  });

  testWidgets('movement beyond slop rejects the press', (tester) async {
    final s = await session(tester);
    s.down(down(), 18);
    s.move(PointerMoveEvent(
        pointer: pointer, position: center + const Offset(40, 0)));
    s.up(up());
    await tester.pump(const Duration(milliseconds: 501));
    expect(emitted, isEmpty);
  });

  testWidgets('reset clears rage history and pending checks', (tester) async {
    final s = await session(tester);
    for (var i = 0; i < 3; i++) {
      tap(s);
    }
    s.reset();
    tap(s);
    s.reset();
    await tester.pump(const Duration(milliseconds: 501));
    expect(emitted, List.filled(4, r'$mp_click:checkout'));
  });
}
