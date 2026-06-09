import 'dart:async';

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

  test(
    'unknown method names raise MissingPluginException to the caller',
    () async {
      final received = <MixpanelEvent>[];
      final sub = MixpanelEventBridge.events.listen(received.add);

      // Flutter's MethodChannel protocol uses a null reply envelope to
      // signal "method not implemented". The Dart handler must propagate
      // this for future native→Dart push features added to the shared
      // channel — silently swallowing unknown methods (the prior
      // behavior) would mask real bugs.
      ByteData? reply;
      final bogus = codec.encodeMethodCall(const MethodCall('somethingElse'));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('mixpanel_flutter', bogus, (data) {
        reply = data;
      });
      await Future<void>.delayed(Duration.zero);

      expect(reply, isNull, reason: 'null reply signals MissingPluginException');
      expect(received, isEmpty);
      await sub.cancel();
    },
  );

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

    test('channel errors from start/stopEventBridge do not escape the zone',
        () async {
      // Engine teardown ordering, missing platform handlers in unit
      // tests, etc. can cause invokeMethod to error after onActivate /
      // onDeactivate is dispatched. Those signals are best-effort and
      // must be swallowed — otherwise an uncaught async error fails the
      // surrounding zone (and unrelated tests).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'TEST_ERROR', message: call.method);
      });

      final errors = <Object>[];
      await runZonedGuarded(() async {
        final sub = MixpanelEventBridge.events.listen((_) {});
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        await Future<void>.delayed(Duration.zero);
      }, (e, _) => errors.add(e));

      expect(errors, isEmpty);
    });
  });
}
