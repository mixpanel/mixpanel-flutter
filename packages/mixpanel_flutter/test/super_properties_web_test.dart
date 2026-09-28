@TestOn('browser')

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter_web.dart';

void main() {
  late JSAny? previousMixpanel;
  late MixpanelFlutterPlugin plugin;
  late List<List<Object?>> calls;

  setUp(() {
    plugin = MixpanelFlutterPlugin();
    calls = [];
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    final sdk = <String, Object?>{}.jsify() as JSObject;
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
  });

  tearDown(() {
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  test('replay properties use page-local JS registration and removal',
      () async {
    // GIVEN a replay ID owned by this page.
    const properties = <String, Object?>{r'$mp_replay_id': 'replay-tab-a'};

    // WHEN replay starts and pauses through the analytics channel.
    await plugin.handleMethodCall(const MethodCall('registerSuperProperties', {
      'properties': properties,
      'persistent': false,
    }));
    await plugin.handleMethodCall(const MethodCall('unregisterSuperProperty', {
      'propertyName': r'$mp_replay_id',
      'persistent': false,
    }));

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

  test('ordinary super properties retain the JS persistence default', () async {
    // GIVEN ordinary application super properties, with no persistence override.
    const properties = <String, Object?>{'plan': 'pro'};

    // WHEN the existing public channel methods are used.
    await plugin.handleMethodCall(const MethodCall('registerSuperProperties', {
      'properties': properties,
    }));
    await plugin.handleMethodCall(const MethodCall('unregisterSuperProperty', {
      'propertyName': 'plan',
    }));

    // THEN JS receives no options override.
    expect(calls, [
      ['register', properties, null],
      ['unregister', 'plan', null],
    ]);
  });
}
