import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// Verifies the reverse path: when the native plugin invokes
/// `onMixpanelEvent` on the channel, the event surfaces on the Dart-side
/// [MixpanelEventBridge.events] stream.
void main() {
  const channel = MethodChannel(
    'mixpanel_flutter',
    StandardMethodCodec(MixpanelMessageCodec()),
  );
  const codec = StandardMethodCodec(MixpanelMessageCodec());

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Force the static initializer in Mixpanel that registers the
    // setMethodCallHandler for 'onMixpanelEvent'. Init touches that path.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await Mixpanel.init(
      'test token',
      optOutTrackingDefault: false,
      trackAutomaticEvents: true,
    );
    // Now release the mock so the real reverse-direction handler installed
    // by Mixpanel.init() can receive simulated native calls.
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
}
