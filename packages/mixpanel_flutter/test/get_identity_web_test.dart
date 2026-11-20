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
  late Duration previousTimeout;

  /// The snippet stub as it looks while mixpanel-js is still loading: it
  /// queues init but has no get_identity.
  JSObject stubSdk() {
    final sdk = <String, Object?>{}.jsify() as JSObject;
    sdk.setProperty('init'.toJS, ((JSString token, JSObject config) {}).toJS);
    return sdk;
  }

  /// The loaded mixpanel-js library, reporting [identity] from get_identity.
  JSObject loadedSdk(Map<String, Object?> identity) {
    final sdk = stubSdk();
    sdk.setProperty(
      'get_identity'.toJS,
      (() => identity.jsify()).toJS,
    );
    return sdk;
  }

  setUp(() {
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    previousTimeout = MixpanelFlutterPlugin.identityLoadTimeout;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, MixpanelFlutterPlugin().handleMethodCall);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
    MixpanelFlutterPlugin.identityLoadTimeout = previousTimeout;
  });

  test(
      'should wait for mixpanel-js to load when getIdentity is called right '
      'after init', () async {
    // GIVEN the public SDK initialized while only the snippet stub is present.
    globalContext.setProperty('mixpanel'.toJS, stubSdk());
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);

    // WHEN getIdentity is called before the library finishes loading, and the
    // library loads afterwards.
    final pending = mixpanel.getIdentity();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    globalContext.setProperty(
      'mixpanel'.toJS,
      loadedSdk({
        'user_id': 'user-1',
        'company_id': 'company-1',
        'device_id': 'device-1',
      }),
    );
    final identity = await pending;

    // THEN the identity is read from the loaded library.
    expect(identity.userId, 'user-1');
    expect(identity.companyId, 'company-1');
    expect(identity.deviceId, 'device-1');
  });

  test('should read the identity immediately once mixpanel-js has loaded',
      () async {
    // GIVEN the loaded library, with no user identified yet.
    globalContext.setProperty(
      'mixpanel'.toJS,
      loadedSdk({'user_id': null, 'company_id': null, 'device_id': 'device-1'}),
    );
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);

    // WHEN getIdentity is called.
    final identity = await mixpanel.getIdentity();

    // THEN only the device id is set.
    expect(identity.userId, isNull);
    expect(identity.companyId, isNull);
    expect(identity.deviceId, 'device-1');
  });

  test(
      'should return an empty identity when mixpanel-js never loads, '
      'for example when an ad blocker blocks it', () async {
    // GIVEN only the snippet stub, which never gets replaced.
    MixpanelFlutterPlugin.identityLoadTimeout =
        const Duration(milliseconds: 200);
    globalContext.setProperty('mixpanel'.toJS, stubSdk());
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);

    // WHEN getIdentity is called.
    final identity = await mixpanel.getIdentity();

    // THEN it resolves with every id null instead of throwing.
    expect(identity.userId, isNull);
    expect(identity.companyId, isNull);
    expect(identity.deviceId, isNull);
  });
}
