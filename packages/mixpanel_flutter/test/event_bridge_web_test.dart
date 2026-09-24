// MixpanelEventBridge is internal to Mixpanel-authored packages.
// ignore_for_file: invalid_use_of_internal_member

@TestOn('browser')

import 'dart:async';
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

  const channel = MethodChannel('mixpanel_flutter');
  late MixpanelFlutterPlugin plugin;
  late JSAny? previousMixpanel;
  late List<String> channelCalls;
  JSObject? capturedConfig;

  setUp(() {
    plugin = MixpanelFlutterPlugin();
    capturedConfig = null;
    channelCalls = [];
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    final jsMixpanel = <String, Object?>{}.jsify() as JSObject;
    jsMixpanel.setProperty(
      'init'.toJS,
      ((JSString token, JSObject config) {
        capturedConfig = config;
      }).toJS,
    );
    globalContext.setProperty('mixpanel'.toJS, jsMixpanel);
    // The mock channel hands every call to the real web plugin, so the
    // public API drives the same plugin code an app would reach.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) {
      channelCalls.add(call.method);
      return plugin.handleMethodCall(call);
    });
  });

  tearDown(() async {
    await plugin.handleMethodCall(const MethodCall('stopEventBridge'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  /// Initializes through the public API and returns the installed hook.
  Future<JSFunction> initWithHook() async {
    await Mixpanel.init(
      'test-token',
      trackAutomaticEvents: false,
      config: <String, dynamic>{
        'hooks': <String, dynamic>{'another_hook': 'keep-me'},
      },
    );
    final hooks = capturedConfig!.getProperty<JSObject>('hooks'.toJS);
    expect(hooks.getProperty<JSString>('another_hook'.toJS).toDart, 'keep-me');
    return hooks.getProperty<JSFunction>('on_track'.toJS);
  }

  /// Subscribes through the public API, which starts the bridge.
  Future<StreamSubscription<MixpanelEvent>> subscribe(
    List<MixpanelEvent> received,
  ) async {
    final sub = MixpanelEventBridge.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);
    return sub;
  }

  test('on_track forwards decorated properties without changing the event',
      () async {
    final hook = await initWithHook();
    final received = <MixpanelEvent>[];
    final sub = await subscribe(received);

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
    final hook = await initWithHook();
    final received = <MixpanelEvent>[];
    final sub = await subscribe(received);

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

  test('subscribing starts and cancelling stops the bridge over the channel',
      () async {
    final hook = await initWithHook();
    final properties = <String, Object?>{'count': 1}.jsify() as JSObject;

    // Tracked before anyone listens: not buffered for a later subscriber.
    hook.callAsFunction(null, 'Before'.toJS, properties);
    final received = <MixpanelEvent>[];
    final sub = await subscribe(received);
    hook.callAsFunction(null, 'During'.toJS, properties);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    await Future<void>.delayed(Duration.zero);
    // Tracking still works while the bridge is stopped.
    final after =
        hook.callAsFunction(null, 'After'.toJS, properties) as JSArray<JSAny?>;

    expect(received.map((event) => event.eventName), ['During']);
    expect(
      channelCalls.where((method) => method.endsWith('EventBridge')),
      ['startEventBridge', 'stopEventBridge'],
    );
    expect((after.toDart[0] as JSString).toDart, 'After');
  });
}
