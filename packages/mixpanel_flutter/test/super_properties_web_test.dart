@TestOn('browser')

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/mixpanel_flutter_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mixpanel_flutter');
  late JSAny? previousMixpanel;
  late List<List<Object?>> calls;

  setUp(() {
    final plugin = MixpanelFlutterPlugin();
    calls = [];
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    final sdk = <String, Object?>{}.jsify() as JSObject;
    sdk.setProperty('init'.toJS, ((JSString token, JSObject config) {}).toJS);
    sdk.setProperty(
      'register'.toJS,
      ((JSAny? properties, [JSAny? options]) {
        calls.add(['register', properties?.dartify(), options?.dartify()]);
      }).toJS,
    );
    sdk.setProperty(
      'unregister'.toJS,
      ((JSString property, [JSAny? options]) {
        calls.add(['unregister', property.toDart, options?.dartify()]);
      }).toJS,
    );
    globalContext.setProperty('mixpanel'.toJS, sdk);
    // The mock channel hands every call to the real web plugin, so the
    // public API drives the same plugin code an app would reach.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, plugin.handleMethodCall);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  /// Initializes through the public API and discards any registration the
  /// SDK performs on its own behalf during startup.
  Future<Mixpanel> initMixpanel() async {
    final mixpanel = await Mixpanel.init(
      'test-token',
      trackAutomaticEvents: false,
    );
    calls.clear();
    return mixpanel;
  }

  test(
      'should keep the JS persistence default when registering ordinary '
      'super properties', () async {
    // GIVEN the public SDK initialized on web.
    final mixpanel = await initMixpanel();

    // WHEN the application registers and removes a super property.
    await mixpanel.registerSuperProperties({'plan': 'pro'});
    await mixpanel.unregisterSuperProperty('plan');

    // THEN JS receives no options override.
    expect(calls, [
      [
        'register',
        {'plan': 'pro'},
        null
      ],
      ['unregister', 'plan', null],
    ]);
  });

  test(
      'should register and remove page-locally when the replay ID is '
      'marked non-persistent', () async {
    // GIVEN the public SDK initialized on web and a replay ID owned by this
    // page.
    await initMixpanel();
    const properties = <String, Object?>{r'$mp_replay_id': 'replay-tab-a'};

    // WHEN the session replay SDK registers and clears its replay ID over the
    // analytics channel, marked page-local the way SessionReplaySender does.
    await channel.invokeMethod<void>('registerSuperProperties', {
      'properties': properties,
      'persistent': false,
    });
    await channel.invokeMethod<void>('unregisterSuperProperty', {
      'propertyName': r'$mp_replay_id',
      'persistent': false,
    });

    // THEN neither operation writes to shared cookies/localStorage.
    expect(calls, [
      [
        'register',
        properties,
        {'persistent': false}
      ],
      [
        'unregister',
        r'$mp_replay_id',
        {'persistent': false}
      ],
    ]);
  });
}
