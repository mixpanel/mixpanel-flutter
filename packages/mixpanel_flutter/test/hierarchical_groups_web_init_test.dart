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
  Map<String, Object?>? initConfig;

  setUp(() {
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    initConfig = null;
    final sdk = <String, Object?>{}.jsify() as JSObject;
    sdk.setProperty(
      'init'.toJS,
      ((JSString token, JSObject config) {
        initConfig = (config.dartify() as Map).cast<String, Object?>();
      }).toJS,
    );
    globalContext.setProperty('mixpanel'.toJS, sdk);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, MixpanelFlutterPlugin().handleMethodCall);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  test('hierarchicalGroups: true turns on hierarchical groups in mixpanel-js',
      () async {
    await Mixpanel.init('token',
        trackAutomaticEvents: false, hierarchicalGroups: true);

    expect(initConfig!['hierarchical_groups'], true);
  });

  test('a hierarchical_groups key in config cannot turn it on', () async {
    await Mixpanel.init('token',
        trackAutomaticEvents: false, config: {'hierarchical_groups': true});

    expect(initConfig!.containsKey('hierarchical_groups'), isFalse);
  });

  test('a hierarchical_groups key in config cannot turn it off', () async {
    await Mixpanel.init('token',
        trackAutomaticEvents: false,
        hierarchicalGroups: true,
        config: {'hierarchical_groups': false});

    expect(initConfig!['hierarchical_groups'], true);
  });

  test('without hierarchical groups, the config has no hierarchical_groups key',
      () async {
    await Mixpanel.init('token',
        trackAutomaticEvents: false, config: {'debug': true});

    expect(initConfig!.containsKey('hierarchical_groups'), isFalse);
    expect(initConfig!['debug'], true);
  });
}
