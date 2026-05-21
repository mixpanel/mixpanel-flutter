import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// Verifies the reverse path: when the native plugin invokes
/// `onMixpanelEvent` on the channel, the event surfaces on the Dart-side
/// [MixpanelEventBridge.events] stream. Also verifies the lazy lifecycle —
/// `startEventBridge` fires on first subscribe, `stopEventBridge` on last
/// cancel.
void main() {
  const channel = MethodChannel(
    'mixpanel_flutter',
    StandardMethodCodec(MixpanelMessageCodec()),
  );
  const codec = StandardMethodCodec(MixpanelMessageCodec());

  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> outgoingCalls;

  setUp(() async {
    outgoingCalls = <MethodCall>[];
    // Persistent mock that records every Dart→native call. Importantly it
    // intercepts the `startEventBridge`/`stopEventBridge` invocations that
    // the lazy lifecycle issues on listener add/cancel, otherwise they'd
    // throw MissingPluginException in the test environment.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      outgoingCalls.add(call);
      return null;
    });
    await Mixpanel.init(
      'test token',
      optOutTrackingDefault: false,
      trackAutomaticEvents: true,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> simulateNativeEvent({
    required String eventName,
    Map<String, Object?>? properties,
  }) async {
    final message = codec.encodeMethodCall(
      MethodCall('onMixpanelEvent', <String, Object?>{
        'eventName': eventName,
        'properties': properties,
      }),
    );
    // handlePlatformMessage bypasses the mock and hits the real
    // MethodCallHandler installed by Mixpanel during init.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('mixpanel_flutter', message, (_) {});
  }

  test(
    'native onMixpanelEvent surfaces on MixpanelEventBridge.events',
    () async {
      final received = <MixpanelEvent>[];
      final sub = MixpanelEventBridge.events.listen(received.add);

      await simulateNativeEvent(
        eventName: 'Button Tapped',
        properties: <String, Object?>{'\$city': 'Brooklyn', 'count': 7},
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first.eventName, 'Button Tapped');
      expect(received.first.properties, {'\$city': 'Brooklyn', 'count': 7});

      await sub.cancel();
    },
  );

  test('null properties from native pass through as null', () async {
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);

    await simulateNativeEvent(eventName: 'no-props');
    await Future<void>.delayed(Duration.zero);

    expect(received.single.eventName, 'no-props');
    expect(received.single.properties, isNull);

    await sub.cancel();
  });

  test('malformed payload (missing eventName) is ignored, no throw', () async {
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);

    final bogus = codec.encodeMethodCall(
      const MethodCall('onMixpanelEvent', <String, Object?>{'properties': {}}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('mixpanel_flutter', bogus, (_) {});
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await sub.cancel();
  });

  test('unknown method names are ignored', () async {
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);

    final bogus = codec.encodeMethodCall(const MethodCall('somethingElse'));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage('mixpanel_flutter', bogus, (_) {});
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await sub.cancel();
  });

  group('lazy native subscription', () {
    test('first Dart listener invokes startEventBridge on the channel',
        () async {
      outgoingCalls.clear();
      final sub = MixpanelEventBridge.events.listen((_) {});
      // The mock handler is called synchronously inside invokeMethod's
      // future chain; one microtask flush is enough to settle it.
      await Future<void>.delayed(Duration.zero);

      expect(
        outgoingCalls.map((c) => c.method).toList(),
        contains('startEventBridge'),
      );

      await sub.cancel();
    });

    test('last Dart cancel invokes stopEventBridge on the channel', () async {
      final sub = MixpanelEventBridge.events.listen((_) {});
      await Future<void>.delayed(Duration.zero);

      outgoingCalls.clear();
      await sub.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(
        outgoingCalls.map((c) => c.method).toList(),
        contains('stopEventBridge'),
      );
    });

    test('start is not issued when no Dart listeners are attached', () async {
      // Nothing subscribes during this test — only Mixpanel.init() ran in
      // setUp, and it must not have triggered the lazy start.
      await Future<void>.delayed(Duration.zero);
      expect(
        outgoingCalls.map((c) => c.method),
        isNot(contains('startEventBridge')),
      );
    });
  });
}
