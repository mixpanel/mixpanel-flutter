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
  late List<String> jsCalls;

  setUp(() {
    final plugin = MixpanelFlutterPlugin();
    jsCalls = [];
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
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

  void setWindowMixpanel(JSAny? value) =>
      globalContext.setProperty('mixpanel'.toJS, value);

  JSFunction recorder(String name) => (() {
        jsCalls.add(name);
      }).toJS;

  /// The snippet's `window.mixpanel` before `mixpanel.init` runs: an array
  /// with only `init`, which installs queueing stubs like the real snippet.
  JSObject snippetStub() {
    final stub = <Object?>[].jsify() as JSObject;
    stub.setProperty(
      'init'.toJS,
      ((JSString token, JSAny? config) {
        stub.setProperty('track'.toJS, recorder('track'));
        stub.setProperty('identify'.toJS, recorder('identify'));
        stub.setProperty('register'.toJS, recorder('register'));
        // Like every snippet stub, this returns undefined.
        stub.setProperty('has_opted_out_tracking'.toJS, (() {}).toJS);
      }).toJS,
    );
    return stub;
  }

  Future<PlatformException> initError() async {
    try {
      await Mixpanel.init('test-token', trackAutomaticEvents: false);
    } on PlatformException catch (e) {
      return e;
    }
    fail('Mixpanel.init should throw when mixpanel-js is unavailable');
  }

  /// Calls every common API through a Mixpanel instance and checks the
  /// getters return the values the Dart API sees when nothing is set.
  Future<void> expectCallsAreSafeNoOps(Mixpanel mixpanel) async {
    mixpanel.track('Event', properties: {'a': 1});
    mixpanel.identify('user-1');
    mixpanel.registerSuperProperties({'plan': 'pro'});
    mixpanel.getPeople().set('name', 'Ada');
    mixpanel.getGroup('company', 'acme').setOnce('size', 'large');
    mixpanel.reset();
    expect(await mixpanel.getDistinctId(), '');
    expect(await mixpanel.hasOptedOutTracking(), isFalse);
    final flags = mixpanel.getFeatureFlags();
    expect(await flags.areFlagsReady(), isFalse);
    expect(await flags.isEnabled('flag', true), isTrue);
    expect(await flags.getVariantValue('flag', 'fallback'), 'fallback');
    await flags.loadFlags();
    await flags.updateContext({'plan': 'pro'});
    expect(jsCalls, isEmpty);
  }

  test(
      'should throw the same PlatformException code as before when '
      'window.mixpanel is missing', () async {
    // GIVEN mixpanel-js was blocked, so window.mixpanel is undefined.
    setWindowMixpanel(null);

    // WHEN the app initializes Mixpanel.
    final error = await initError();

    // THEN init throws with the unchanged `error` code, and later calls
    // are safe no-ops.
    expect(error.code, 'error');
    await expectCallsAreSafeNoOps(Mixpanel('test-token'));
  });

  test(
      'should throw the same PlatformException code as before when '
      'mixpanel.init is not callable', () async {
    // GIVEN some other script defined window.mixpanel without init.
    setWindowMixpanel(<String, Object?>{}.jsify());

    // WHEN / THEN init throws with the unchanged `error` code.
    expect((await initError()).code, 'error');
  });

  test(
      'should rethrow the init error unchanged and keep calling mixpanel-js '
      'when mixpanel.init throws', () async {
    // GIVEN a mixpanel-js whose init throws.
    final sdk = <String, Object?>{}.jsify() as JSObject;
    sdk.setProperty(
      'init'.toJS,
      ((JSString token, JSAny? config) {
        if (token.toDart.isNotEmpty) throw 'boom'.toJS;
      }).toJS,
    );
    sdk.setProperty('track'.toJS, recorder('track'));
    setWindowMixpanel(sdk);

    // WHEN the app initializes Mixpanel and tracks anyway.
    final error = await initError();
    await Mixpanel('test-token').track('Event');

    // THEN init throws as before, and later calls still reach mixpanel-js.
    expect(error.code, 'error');
    expect(error.message, contains('boom'));
    expect(jsCalls, ['track']);
  });

  test('should resume calls when a later init succeeds', () async {
    // GIVEN a failed init because mixpanel-js was missing.
    setWindowMixpanel(null);
    await initError();

    // WHEN mixpanel-js becomes available and init is retried.
    setWindowMixpanel(snippetStub());
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);
    await mixpanel.track('Event');

    // THEN calls reach mixpanel-js again.
    expect(jsCalls, ['track']);
  });

  test('should drop calls made before init without a JS TypeError', () async {
    // GIVEN the snippet is on the page but Mixpanel.init has not run, so
    // window.mixpanel.track does not exist yet.
    setWindowMixpanel(snippetStub());
    final early = Mixpanel('test-token');

    // WHEN the app calls Mixpanel before init.
    await early.track('Early');
    await early.identify('user-1');
    expect(await early.getDistinctId(), '');

    // THEN the calls are dropped, and calls after init reach the stub.
    expect(jsCalls, isEmpty);
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);
    await mixpanel.track('Event');
    await mixpanel.identify('user-1');
    await mixpanel.registerSuperProperties({'plan': 'pro'});
    expect(jsCalls, ['track', 'identify', 'register']);
  });

  test('should report not opted out while the snippet stub is active',
      () async {
    // GIVEN init ran on the snippet, but mixpanel-js has not loaded, so
    // the stubs return undefined and getters are not defined yet.
    setWindowMixpanel(snippetStub());
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);

    // WHEN / THEN getters return their "nothing set" values.
    expect(await mixpanel.hasOptedOutTracking(), isFalse);
    expect(await mixpanel.getDistinctId(), '');
  });

  for (final optedOut in [true, false]) {
    test('should return $optedOut when mixpanel-js reports opted out $optedOut',
        () async {
      // GIVEN a loaded mixpanel-js whose has_opted_out_tracking returns
      // a real boolean.
      final sdk = <String, Object?>{}.jsify() as JSObject;
      sdk.setProperty('init'.toJS, ((JSString token, JSAny? config) {}).toJS);
      sdk.setProperty(
        'has_opted_out_tracking'.toJS,
        (() => optedOut.toJS).toJS,
      );
      setWindowMixpanel(sdk);
      final mixpanel =
          await Mixpanel.init('test-token', trackAutomaticEvents: false);

      // WHEN / THEN the Dart API returns the same value.
      expect(await mixpanel.hasOptedOutTracking(), optedOut);
    });
  }
}
