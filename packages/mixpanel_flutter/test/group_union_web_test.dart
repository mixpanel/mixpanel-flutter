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
  late List<List<Object?>> unions;

  setUp(() {
    final plugin = MixpanelFlutterPlugin();
    unions = [];
    previousMixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    final group = <String, Object?>{}.jsify() as JSObject;
    group.setProperty(
      'union'.toJS,
      ((JSString name, JSAny? values) {
        unions.add([name.toDart, values.dartify()]);
      }).toJS,
    );
    final sdk = <String, Object?>{}.jsify() as JSObject;
    sdk.setProperty('init'.toJS, ((JSString token, JSObject config) {}).toJS);
    sdk.setProperty('register'.toJS, ((JSAny? p, [JSAny? o]) {}).toJS);
    sdk.setProperty(
        'get_group'.toJS, ((JSString key, JSAny? id) => group).toJS);
    globalContext.setProperty('mixpanel'.toJS, sdk);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, plugin.handleMethodCall);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    globalContext.setProperty('mixpanel'.toJS, previousMixpanel);
  });

  test('groupUnionProperty passes list values to JS as an array', () async {
    final mixpanel =
        await Mixpanel.init('test-token', trackAutomaticEvents: false);

    mixpanel.getGroup('company', 'acme').union('tags', ['a', 'b']);
    await Future<void>.delayed(Duration.zero);

    expect(unions, [
      [
        'tags',
        ['a', 'b']
      ]
    ]);
  });
}
