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
  late Map<Object?, Object?>? initConfig;
  late List<Object?> setConfigCalls;

  setUp(() {
    final plugin = MixpanelFlutterPlugin();
    initConfig = null;
    setConfigCalls = [];
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    final sdk = <String, Object?>{}.jsify() as JSObject;
    sdk.setProperty(
      'init'.toJS,
      ((JSString token, JSObject config) {
        initConfig = config.dartify() as Map<Object?, Object?>;
      }).toJS,
    );
    sdk.setProperty(
      'set_config'.toJS,
      ((JSAny? config) {
        setConfigCalls.add(config?.dartify());
      }).toJS,
    );
    globalContext.setProperty('mixpanel'.toJS, sdk);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, plugin.handleMethodCall);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  test('init maps useIpAddressForGeolocation to the ip config', () async {
    await Mixpanel.init(
      'test-token',
      trackAutomaticEvents: false,
      useIpAddressForGeolocation: false,
    );
    expect(initConfig!['ip'], isFalse);
  });

  test('init leaves ip unset when useIpAddressForGeolocation is omitted',
      () async {
    await Mixpanel.init('test-token', trackAutomaticEvents: false);
    expect(initConfig!.containsKey('ip'), isFalse);
  });

  test('init keeps an ip value passed through config when omitted', () async {
    await Mixpanel.init(
      'test-token',
      trackAutomaticEvents: false,
      config: {'ip': false},
    );
    expect(initConfig!['ip'], isFalse);
  });

  test('setUseIpAddressForGeolocation calls set_config with ip', () async {
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);
    mixpanel.setUseIpAddressForGeolocation(false);
    await Future<void>.delayed(Duration.zero);
    mixpanel.setUseIpAddressForGeolocation(true);
    await Future<void>.delayed(Duration.zero);
    expect(setConfigCalls, [
      {'ip': false},
      {'ip': true},
    ]);
  });
}
