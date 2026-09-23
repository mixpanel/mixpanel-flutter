// MixpanelEventBridge is internal to Mixpanel-authored packages.
// ignore_for_file: invalid_use_of_internal_member

@TestOn('browser')

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/mixpanel_flutter_web.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

@JS('Date')
@staticInterop
class _JSDate {
  external factory _JSDate(String value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MixpanelFlutterPlugin plugin;
  late JSAny? previousMixpanel;
  JSObject? capturedConfig;

  setUp(() {
    plugin = MixpanelFlutterPlugin();
    capturedConfig = null;
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    final jsMixpanel = <String, Object?>{}.jsify() as JSObject;
    jsMixpanel.setProperty(
      'init'.toJS,
      ((JSString token, JSObject config) {
        capturedConfig = config;
      }).toJS,
    );
    globalContext.setProperty('mixpanel'.toJS, jsMixpanel);
  });

  tearDown(() async {
    await plugin.handleMethodCall(const MethodCall('stopEventBridge'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('mixpanel_flutter'), null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  JSFunction installedHook() {
    plugin.initialize(const MethodCall('initialize', <String, Object?>{
      'token': 'test-token',
      'config': <String, Object?>{
        'hooks': <String, Object?>{'another_hook': 'keep-me'},
      },
    }));
    final hooks = capturedConfig!.getProperty<JSObject>('hooks'.toJS);
    expect(hooks.getProperty<JSString>('another_hook'.toJS).toDart, 'keep-me');
    return hooks.getProperty<JSFunction>('on_track'.toJS);
  }

  test('on_track forwards decorated properties without changing the event',
      () async {
    final hook = installedHook();
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);
    await plugin.handleMethodCall(const MethodCall('startEventBridge'));

    final properties = <String, Object?>{
      'plan': 'pro',
      'nested': <String, Object?>{'seats': 3},
      'distinct_id': 'user-1',
    }.jsify() as JSObject;
    final result = hook.callAsFunction(
      null,
      'Checkout'.toJS,
      properties,
    ) as JSArray<JSAny?>;
    await Future<void>.delayed(Duration.zero);

    expect((result.toDart[0] as JSString).toDart, 'Checkout');
    expect(result.toDart[1], same(properties));
    expect(received.single.eventName, 'Checkout');
    expect(received.single.properties, containsPair('plan', 'pro'));
    expect(received.single.properties,
        containsPair('nested', <String, Object?>{'seats': 3}));
    await sub.cancel();
  });

  test('on_track forwards JS dates without dropping the event', () async {
    final hook = installedHook();
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);
    await plugin.handleMethodCall(const MethodCall('startEventBridge'));

    final date = _JSDate('2024-03-10T04:30:00-05:00');
    final properties = <String, Object?>{
      'occurred_at': date,
      'nested': <String, Object?>{
        'dates': <Object?>[date]
      },
    }.jsify() as JSObject;
    final result = hook.callAsFunction(
      null,
      'Dated event'.toJS,
      properties,
    ) as JSArray<JSAny?>;
    await Future<void>.delayed(Duration.zero);

    expect(result.toDart[1], same(properties));
    expect(received, hasLength(1));
    expect(received.single.properties?['occurred_at'],
        DateTime.utc(2024, 3, 10, 9, 30));
    expect(received.single.properties?['nested'], {
      'dates': [DateTime.utc(2024, 3, 10, 9, 30)],
    });
    await sub.cancel();
  });

  test('start and stop gate forwarding while leaving tracking intact',
      () async {
    final hook = installedHook();
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);
    final properties = <String, Object?>{'count': 1}.jsify() as JSObject;

    hook.callAsFunction(null, 'Before'.toJS, properties);
    await plugin.handleMethodCall(const MethodCall('startEventBridge'));
    hook.callAsFunction(null, 'During'.toJS, properties);
    await plugin.handleMethodCall(const MethodCall('stopEventBridge'));
    hook.callAsFunction(null, 'After'.toJS, properties);
    await Future<void>.delayed(Duration.zero);

    expect(received.map((event) => event.eventName), ['During']);
    await sub.cancel();
  });

  test('Mixpanel init activates the JS bridge for a Dart listener', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('mixpanel_flutter'),
      plugin.handleMethodCall,
    );
    await Mixpanel.init('test-token', trackAutomaticEvents: false);
    final hook = capturedConfig!
        .getProperty<JSObject>('hooks'.toJS)
        .getProperty<JSFunction>('on_track'.toJS);
    final received = <MixpanelEvent>[];
    final sub = MixpanelEventBridge.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    hook.callAsFunction(
      null,
      'Subscribed'.toJS,
      <String, Object?>{'plan': 'team'}.jsify() as JSObject,
    );
    await Future<void>.delayed(Duration.zero);
    expect(received.single.eventName, 'Subscribed');

    await sub.cancel();
    await Future<void>.delayed(Duration.zero);
    hook.callAsFunction(null, 'Unsubscribed'.toJS, null);
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
  });
}
