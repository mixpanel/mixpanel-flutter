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

  Widget host(Widget child) => MixpanelAutocaptureWidget(
      instance: instance,
      child: MaterialApp(home: Scaffold(body: Center(child: child))));
  List<Map<dynamic, dynamic>> named(String name) =>
      events.where((e) => e['eventName'] == name).toList();

  setUp(() {
    events.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
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

  // Only the deadline state is compared, so a response that
  // fully reverts before the deadline is not observed.
  testWidgets('response reverted before the deadline is not observed',
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
    await tester.pump();
    expect(named(r'$mp_dead_click'), hasLength(1));
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
    testWidgets('independent flags $mask and burst reset', (tester) async {
      await init(AutocaptureOptions(
          clickOptions: ClickOptions(enabled: mask & 1 != 0),
          rageClickOptions: RageClickOptions(enabled: mask & 2 != 0),
          deadClickOptions: DeadClickOptions(enabled: mask & 4 != 0)));
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

  testWidgets('omitted options emit nothing', (tester) async {
    await init(null);
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(seconds: 1));
    expect(events, isEmpty);
  });

  for (final operation in ['identify', 'reset']) {
    testWidgets('$operation cancels a pending dead check', (tester) async {
      await init();
      await tester.pumpWidget(host(button()));
      await tester.tap(find.text('Buy'));
      // A separate handle shares the same native identity.
      final other = Mixpanel('test');
      await (operation == 'identify' ? other.identify('user') : other.reset());
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump();
      expect(named(r'$mp_click'), hasLength(1));
      expect(named(r'$mp_dead_click'), isEmpty);

      // Detection continues for later taps.
      await tester.tap(find.text('Buy'));
      await tester.pump(const Duration(milliseconds: 501));
      await tester.pump();
      expect(named(r'$mp_dead_click'), hasLength(1));
    });
  }

  testWidgets('long press, cancelled and swipe-return gestures are rejected',
      (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    final p = tester.getCenter(find.text('Buy'));
    var gesture = await tester.startGesture(p);
    await tester.pump(const Duration(milliseconds: 501));
    await gesture.up(timeStamp: const Duration(milliseconds: 501));
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

  testWidgets('nested wrappers are rejected in debug', (tester) async {
    await init();
    await tester.pumpWidget(
        host(MixpanelAutocaptureWidget(instance: instance, child: button())));
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('enabling capture after init keeps child state', (tester) async {
    await init();
    final key = GlobalKey();
    Widget app(Mixpanel? value) => MixpanelAutocaptureWidget(
        instance: value,
        child: MaterialApp(
            home: Scaffold(
                body: Center(
                    child: StatefulBuilder(
                        key: key, builder: (_, __) => button())))));
    await tester.pumpWidget(app(null));
    final state = key.currentState;
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(seconds: 1));
    expect(events, isEmpty);

    await tester.pumpWidget(app(instance));
    expect(key.currentState, same(state));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(named(r'$mp_click'), hasLength(1));
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

  testWidgets('visible scrollbar does not suppress dead detection',
      (tester) async {
    await init();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: ListView(controller: controller, children: [
          button(),
          for (var i = 0; i < 30; i++) const SizedBox(height: 40),
        ]))));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), hasLength(1));
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

  testWidgets('unmount clears pending timers', (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('navigation and background cancel pending dead clicks',
      (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    // A route change is a screen change, cancelling through the snapshot.
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Text('Next')));
    await tester.pump(const Duration(milliseconds: 501));
    await tester.pump();
    expect(named(r'$mp_dead_click'), isEmpty);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
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

  testWidgets('exactly 500 ms is a tap', (tester) async {
    await init();
    await tester.pumpWidget(host(button()));
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Buy')));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up(timeStamp: const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
  });

  testWidgets(
      'unrelated large render subtree does not suppress target resolution',
      (tester) async {
    await init(const AutocaptureOptions(
        deadClickOptions: DeadClickOptions(enabled: false)));
    await tester.pumpWidget(host(Stack(children: [
      // A mounted tree well above the old 2,000-node budget, not on hit path.
      IgnorePointer(
          child: Column(
              children: List.generate(
                  2500, (_) => const SizedBox(width: 1, height: 0)))),
      Center(child: button()),
    ])));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_click').single['properties'][r'$el_id'], 'checkout');
  });

  testWidgets('transformed button retains target and no-response detection',
      (tester) async {
    await init();
    await tester.pumpWidget(host(Transform.translate(
        offset: const Offset(40, 25),
        child: Transform.scale(scale: 1.2, child: button()))));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), hasLength(1));
  });

  testWidgets('snapshot overflow suppresses dead but hit-path click survives',
      (tester) async {
    await init();
    await tester.pumpWidget(host(Stack(children: [
      for (var i = 0; i < 2100; i++) const SizedBox(width: 5, height: 5),
      Center(child: button()),
    ])));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('radio effective checked state counts as a response',
      (tester) async {
    await init();
    var selected = false;
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (_, setState) => Column(children: [
              button(onPressed: () => setState(() => selected = true)),
              Radio<bool>(
                  value: true,
                  // Keep this regression runnable on Flutter 3.19, before RadioGroup.
                  // ignore: deprecated_member_use
                  groupValue: selected,
                  // ignore: deprecated_member_use
                  onChanged: (_) {}),
            ]))));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('zero-sized portal host resolves distinct overlay owners',
      (tester) async {
    await init();
    final portal = OverlayPortalController();
    await tester.pumpWidget(host(OverlayPortal(
      controller: portal,
      overlayChildBuilder: (_) => Positioned(
          left: 40,
          top: 140,
          child: Material(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            button(id: 'portal_one', child: const Text('Portal One')),
            button(id: 'portal_two', child: const Text('Portal Two')),
          ]))),
      child: const SizedBox.shrink(),
    )));
    portal.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portal One'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_dead_click'), hasLength(1));
    await tester.tap(find.text('Portal Two'));
    await tester.pump(const Duration(milliseconds: 501));
    final clicks = named(r'$mp_click');
    expect(clicks.map((e) => e['properties'][r'$el_id']),
        ['portal_one', 'portal_two']);
    expect(
        clicks
            .every((e) => e['properties'][r'$el_tag_name'] == 'ElevatedButton'),
        isTrue);
    expect(clicks.every((e) => e['properties'][r'$attr-role'] == 'Button'),
        isTrue);
    expect(named(r'$mp_dead_click'), hasLength(2));
  });

  testWidgets('response in overlay of zero-sized host cancels dead detection',
      (tester) async {
    await init();
    final portal = OverlayPortalController();
    var label = 'AAAA';
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (_, setState) => Column(children: [
              button(onPressed: () => setState(() => label = 'BBBB')),
              OverlayPortal(
                  controller: portal,
                  overlayChildBuilder: (_) => Positioned(
                      left: 30, top: 400, child: Material(child: Text(label))),
                  child: const SizedBox.shrink()),
            ]))));
    portal.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('MenuAnchor items keep distinct actionable attribution',
      (tester) async {
    await init();
    final menu = MenuController();
    await tester.pumpWidget(host(MenuAnchor(
        controller: menu,
        menuChildren: [
          MenuItemButton(onPressed: () {}, child: const Text('Item One')),
          MenuItemButton(onPressed: () {}, child: const Text('Item Two')),
        ],
        builder: (_, controller, child) => ElevatedButton(
            onPressed: controller.open, child: const Text('Open menu')))));
    final ids = <String>[];
    for (final label in ['Item One', 'Item Two']) {
      menu.open();
      await tester.pumpAndSettle();
      events.clear();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      final props = named(r'$mp_click').single['properties'];
      expect(props[r'$el_tag_name'], 'TextButton');
      expect(props[r'$attr-role'], 'Button');
      ids.add(props[r'$el_id'] as String);
    }
    expect(ids.toSet(), hasLength(2));
  });

  testWidgets(
      'over-budget portal fallback skips instead of naming root listener',
      (tester) async {
    await init(const AutocaptureOptions(
        deadClickOptions: DeadClickOptions(enabled: false)));
    final portal = OverlayPortalController();
    await tester.pumpWidget(host(Stack(children: [
      IgnorePointer(
          child: Column(
              children: List.generate(
                  2500, (_) => const SizedBox(width: 1, height: 0)))),
      OverlayPortal(
          controller: portal,
          overlayChildBuilder: (_) => Positioned(
              left: 40,
              top: 140,
              child: Material(child: button(id: 'portal_over_budget'))),
          child: const SizedBox.shrink()),
    ])));
    portal.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(events, isEmpty);
  });

  testWidgets('proven offscreen custom painter does not veto dead clicks',
      (tester) async {
    await init();
    await tester.pumpWidget(host(Stack(children: [
      Transform.translate(
          offset: const Offset(5000, 0),
          child: CustomPaint(painter: _Painter(), size: const Size(20, 20))),
      Center(child: button()),
    ])));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), hasLength(1));
  });

  for (final offscreen in [false, true]) {
    testWidgets(
        'texture visibility controls dead suppression: offscreen=$offscreen',
        (tester) async {
      await init();
      await tester.pumpWidget(host(Stack(children: [
        Transform.translate(
            offset: Offset(offscreen ? 5000 : 0, 0),
            child: const SizedBox(
                width: 20, height: 20, child: Texture(textureId: 999))),
        Center(child: button()),
      ])));
      await tester.tap(find.text('Buy'));
      await tester.pump(const Duration(milliseconds: 501));
      expect(named(r'$mp_click'), hasLength(1));
      expect(named(r'$mp_dead_click'), hasLength(offscreen ? 1 : 0));
    });
  }

  testWidgets('visible portal painter vetoes despite sized offscreen host',
      (tester) async {
    await init();
    final portal = OverlayPortalController();
    await tester.pumpWidget(host(Stack(children: [
      Transform.translate(
          offset: const Offset(5000, 0),
          child: SizedBox(
              width: 80,
              height: 80,
              child: OverlayPortal(
                  controller: portal,
                  overlayChildBuilder: (_) => Positioned(
                      left: 20,
                      top: 150,
                      child: CustomPaint(
                          painter: _Painter(), size: const Size(20, 20))),
                  child: const SizedBox.expand()))),
      Center(child: button()),
    ])));
    portal.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('visible portal response under sized offscreen host cancels dead',
      (tester) async {
    await init();
    final portal = OverlayPortalController();
    var label = 'AAAA';
    await tester.pumpWidget(host(StatefulBuilder(
        builder: (_, setState) => Stack(children: [
              Transform.translate(
                  offset: const Offset(5000, 0),
                  child: SizedBox(
                      width: 80,
                      height: 80,
                      child: OverlayPortal(
                          controller: portal,
                          overlayChildBuilder: (_) => Positioned(
                              left: 20,
                              top: 150,
                              child: Material(child: Text(label))),
                          child: const SizedBox.expand()))),
              Center(
                  child:
                      button(onPressed: () => setState(() => label = 'BBBB'))),
            ]))));
    portal.show();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 501));
    expect(named(r'$mp_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  for (final offscreen in [false, true]) {
    testWidgets('stateful platform surface bounds: offscreen=$offscreen',
        (tester) async {
      await init();
      await tester.pumpWidget(host(Stack(children: [
        Transform.translate(
            offset: Offset(offscreen ? 5000 : 0, 0),
            child: const _GeometryOnlyAndroidView()),
        Center(child: button()),
      ])));
      await tester.tap(find.text('Buy'));
      await tester.pump(const Duration(milliseconds: 501));
      expect(named(r'$mp_click'), hasLength(1));
      expect(named(r'$mp_dead_click'), hasLength(offscreen ? 1 : 0));
    });
  }

  testWidgets('nested rage settings work when basic click emission is disabled',
      (tester) async {
    await init(const AutocaptureOptions(
      clickOptions: ClickOptions(enabled: false),
      rageClickOptions: RageClickOptions(
          clickThreshold: 2,
          timeWindow: Duration(milliseconds: 100),
          radius: 8),
      deadClickOptions: DeadClickOptions(enabled: false),
    ));
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.text('Buy'));
    await tester.pump();
    expect(named(r'$mp_click'), isEmpty);
    expect(named(r'$mp_rage_click'), hasLength(1));
    expect(named(r'$mp_dead_click'), isEmpty);
  });

  testWidgets('nested dead window controls deadline independently',
      (tester) async {
    await init(const AutocaptureOptions(
      clickOptions: ClickOptions(enabled: false),
      rageClickOptions: RageClickOptions(enabled: false),
      deadClickOptions:
          DeadClickOptions(timeWindow: Duration(milliseconds: 100)),
    ));
    await tester.pumpWidget(host(button()));
    await tester.tap(find.text('Buy'));
    await tester.pump(const Duration(milliseconds: 99));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(named(r'$mp_click'), isEmpty);
    expect(named(r'$mp_rage_click'), isEmpty);
    expect(named(r'$mp_dead_click'), hasLength(1));
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

// Exercise AndroidView's StatefulElement geometry path without native channels.
// This fixture validates visibility resolution, not native platform rendering.
class _GeometryOnlyAndroidView extends AndroidView {
  const _GeometryOnlyAndroidView() : super(viewType: 'geometry-test');
  @override
  State<AndroidView> createState() => _GeometryOnlyAndroidViewState();
}

class _GeometryOnlyAndroidViewState extends State<AndroidView> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 20, height: 20);
}
