import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/src/autocapture/target_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
      'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
  final events = <Map<dynamic, dynamic>>[];
  bool? optedOut;
  late Mixpanel instance;
  Future<Mixpanel> init(
      [AutocaptureOptions? options = const AutocaptureOptions()]) async {
    instance = await Mixpanel.init('test',
        trackAutomaticEvents: false, autocaptureOptions: options);
    return instance;
  }

  Widget button(
      {VoidCallback? onPressed, String? id = 'checkout', Widget? child}) {
    final b = ElevatedButton(
        onPressed: onPressed ?? () {}, child: child ?? const Text('Buy'));
    return id == null ? b : Semantics(identifier: id, child: b);
  }

  Widget host(Widget child, {List<NavigatorObserver> observers = const []}) =>
      MixpanelAutocaptureWidget(
          instance: instance,
          child: MaterialApp(
              navigatorObservers: observers,
              home: Scaffold(body: Center(child: child))));
  List<Map<dynamic, dynamic>> named(String name) =>
      events.where((e) => e['eventName'] == name).toList();

  setUp(() {
    events.clear();
    optedOut = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hasOptedOutTracking') return optedOut;
      if (call.method == 'optOutTracking') optedOut = true;
      if (call.method == 'optInTracking') optedOut = false;
      if (call.method == 'track') events.add(call.arguments as Map);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets('no-op button reports owner click and dead despite ripple',
      (tester) async {
    await init();
    await tester.pumpWidget(host(button(
        child: Semantics(
            identifier: 'leaf-id',
            label: 'private@example.com',
            child: const Text('Buy')))));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(named(r'$mp_click'), hasLength(1));
    final props = named(r'$mp_click').single['properties'];
    expect(props[r'$el_id'], 'checkout');
    expect(props[r'$el_tag_name'], 'ElevatedButton');
    expect(props.toString(), isNot(contains('private@example.com')));
    expect(props.toString(), isNot(contains('leaf-id')));
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(named(r'$mp_dead_click'), hasLength(1));
  }, semanticsEnabled: false);

  testWidgets('same-sized text update elsewhere cancels dead', (tester) async {
    await init();
    var text = 'AAAA';
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => Column(children: [
              button(onPressed: () => setState(() => text = 'BBBB')),
              Text(text),
            ]))));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('transient text response remains a response after disappearing',
      (tester) async {
    await init();
    var visible = false;
    late StateSetter update;
    await tester.pumpWidget(host(StatefulBuilder(builder: (context, setState) {
      update = setState;
      return Column(children: [
        button(onPressed: () => setState(() => visible = true)),
        if (visible) const Text('Response')
      ]);
    })));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    update(() => visible = false);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('new noninteractive tap cancels old dead check', (tester) async {
    await init();
    await tester
        .pumpWidget(host(Column(children: [button(), const Text('Plain')])));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Plain'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(2));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  for (var mask = 0; mask < 8; mask++) {
    testWidgets('independent flags $mask and Android burst reset',
        (tester) async {
      await init(AutocaptureOptions(
          click: mask & 1 != 0,
          rageClick: mask & 2 != 0,
          deadClick: mask & 4 != 0));
      await tester.pumpWidget(host(button()));
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.text('Buy'));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump();
      expect(named(r'$mp_click'), hasLength(mask & 1 != 0 ? 8 : 0));
      expect(named(r'$mp_rage_click'), hasLength(mask & 2 != 0 ? 2 : 0));
      expect(named(r'$mp_dead_click'), hasLength(mask & 4 != 0 ? 1 : 0));
    });
  }

  testWidgets('omitted options and unknown/persisted opt-out emit nothing',
      (tester) async {
    await init(null);
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    for (final state in [true, null]) {
      optedOut = state;
      await init();
      await tester.pumpWidget(host(button()));
      await tester.tap(find.text('Buy'));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(events, isEmpty);
  });

  testWidgets('opt-out immediately cancels pending work; opt-in resumes',
      (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    instance.optOutTracking();
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(seconds: 1));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
    instance.optInTracking();
    await tester.pump();
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(named(r'$mp_click'), hasLength(2));
    expect(named(r'$mp_dead_click'), hasLength(1));
  });

  testWidgets('reset invalidates pending events', (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    await instance.reset();
    await tester.pump(const Duration(seconds: 1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('long press, cancelled and swipe-return gestures are rejected',
      (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    final p = tester.getCenter(find.text('Buy'));
    var gesture = await tester.startGesture(p);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up(timeStamp: const Duration(milliseconds: 500));
    gesture = await tester.startGesture(p);
    await gesture.moveTo(p + const Offset(100, 0));
    await gesture.moveTo(p);
    await gesture.up();
    gesture = await tester.startGesture(p);
    await gesture.cancel();
    await tester.pump(const Duration(seconds: 1));
    expect(events, isEmpty);
  });

  testWidgets('multi-touch invalidates first finger too', (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    final p = tester.getCenter(find.text('Buy'));
    final one = await tester.startGesture(p, pointer: 1);
    final two = await tester.startGesture(p + const Offset(5, 0), pointer: 2);
    await two.up();
    await one.up();
    await tester.pump(const Duration(seconds: 1));
    expect(events, isEmpty);
  });

  testWidgets('nested wrappers do not double capture', (tester) async {
    await init();
    await tester.pumpWidget(
        host(MixpanelAutocaptureWidget(instance: instance, child: button())));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), hasLength(1));
  });

  testWidgets('unsupported custom paint anywhere suppresses dead only',
      (tester) async {
    await init();
    await tester.pumpWidget(host(Column(children: [
      button(),
      CustomPaint(painter: _Painter(), size: const Size(20, 20))
    ])));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(seconds: 1));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('disabled button has no dead event', (tester) async {
    await init();
    await tester.pumpWidget(
        host(const ElevatedButton(onPressed: null, child: Text('Disabled'))));
    await tester.tap(find.text('Disabled'));
    await tester.pump(const Duration(seconds: 1));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets(
      'unmount clears timers without remounting child on consent change',
      (tester) async {
    await init();
    var builds = 0;
    final key = GlobalKey();
    await tester.pumpWidget(host(StatefulBuilder(
        key: key,
        builder: (_, __) {
          builds++;
          return button();
        })));
    final state = key.currentState;
    instance.optOutTracking();
    await tester.pump();
    expect(key.currentState, same(state));
    expect(builds, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation and background cancel pending dead clicks',
      (tester) async {
    await init();
    final observer = MixpanelAutocaptureNavigatorObserver(instance: instance);
    await tester.pumpWidget(host(button(), observers: [observer]));
    await tester.tap(find.text('Buy'));
    observer.didPush(
        MaterialPageRoute<void>(builder: (_) => const SizedBox()), null);
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_dead_click'), isEmpty);
    await tester.tap(find.text('Buy'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_dead_click'), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('color changes elsewhere count as a response', (tester) async {
    await init();
    var color = Colors.red;
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => Column(children: [
              button(onPressed: () => setState(() => color = Colors.blue)),
              ColoredBox(
                  color: color, child: const SizedBox(width: 20, height: 20))
            ]))));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('editable values and keys never enter event metadata',
      (tester) async {
    await init();
    await tester.pumpWidget(host(const TextField(
        key: ValueKey('private-key@example.com'),
        obscureText: true,
        decoration: InputDecoration(labelText: 'private-label@example.com'))));
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'private-password');
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
    expect(events.toString(), isNot(contains('private-')));
  });

  testWidgets('iOS Cupertino button resolves its public owner', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await init();
    await tester.pumpWidget(host(Semantics(
        identifier: 'cupertino-owner',
        child: CupertinoButton(onPressed: () {}, child: const Text('Buy')))));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(
        named(r'$mp_click').single['properties'][r'$el_id'], 'cupertino-owner');
    expect(named(r'$mp_click').single['properties'][r'$el_tag_name'],
        'CupertinoButton');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('nested custom gesture keeps identity inside a button',
      (tester) async {
    await init();
    await tester.pumpWidget(host(button(
        child: Semantics(
            identifier: 'inner',
            child: GestureDetector(onTap: () {}, child: const Text('Buy'))))));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click').single['properties'][r'$el_id'], 'inner');
    expect(named(r'$mp_click').single['properties'][r'$el_tag_name'],
        'GestureDetector');
  });

  test('structural hash uses specified FNV-1a bytes', () {
    expect(TargetResolver.stableHash('hello'), '4f9f2cab');
  });
}

class _Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_Painter oldDelegate) => false;
}
