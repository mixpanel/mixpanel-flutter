// MixpanelEventBridge is internal to Mixpanel-authored packages.
// ignore_for_file: invalid_use_of_internal_member

/// Exercises the `on_track` hook against the real mixpanel-js library.
///
/// The other web bridge tests stub `mixpanel.init` and call the captured hook
/// directly, so they cannot tell whether the real library still invokes the
/// hook or still honors its return value. This suite loads the library the way
/// an app does and tracks through the public API.
///
/// It deliberately tracks `mixpanel-2-latest` rather than a pinned version,
/// because that is what the shipped snippet loads in production. A failure here
/// on an unrelated PR most likely means mixpanel-js changed the hook contract
/// upstream, not that the PR broke something.
///
/// Requires network access to cdn.mxpnl.com.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';
import 'package:mixpanel_flutter/mixpanel_flutter_web.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// Marks the fake API host so the shim only captures this suite's requests.
const _apiHost = 'http://localhost/__mixpanel_flutter_test__';

/// Captures outgoing track requests instead of letting them reach the network.
const _captureShim = r"""
window.__mpSent = [];
(function () {
  var open = XMLHttpRequest.prototype.open;
  var send = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__mpUrl = url;
    return open.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function (body) {
    if (this.__mpUrl &&
        String(this.__mpUrl).indexOf('__mixpanel_flutter_test__') !== -1) {
      window.__mpSent.push(String(body));
      var xhr = this;
      Object.defineProperty(this, 'readyState', {value: 4});
      Object.defineProperty(this, 'status', {value: 200});
      Object.defineProperty(this, 'responseText', {value: '1'});
      setTimeout(function () {
        if (xhr.onreadystatechange) xhr.onreadystatechange();
        if (xhr.onload) xhr.onload();
      }, 0);
      return;
    }
    return send.apply(this, arguments);
  };
})();
""";

/// A copy of `assets/mixpanel.js`, the loader snippet apps paste into their
/// `index.html`. It queues `init` and pulls mixpanel-2-latest from the CDN.
const _loaderSnippet = r"""
(function(f,b){if(!b.__SV){var e,g,i,h;window.mixpanel=b;b._i=[];b.init=function(e,f,c){function g(a,d){var b=d.split(".");2==b.length&&(a=a[b[0]],d=b[1]);a[d]=function(){a.push([d].concat(Array.prototype.slice.call(arguments,0)))}}var a=b;"undefined"!==typeof c?a=b[c]=[]:c="mixpanel";a.people=a.people||[];a.toString=function(a){var d="mixpanel";"mixpanel"!==c&&(d+="."+c);a||(d+=" (stub)");return d};a.people.toString=function(){return a.toString(1)+".people (stub)"};i="disable time_event track track_pageview track_links track_forms track_with_groups add_group set_group remove_group register register_once alias unregister identify name_tag set_config reset opt_in_tracking opt_out_tracking has_opted_in_tracking has_opted_out_tracking clear_opt_in_out_tracking start_batch_senders people.set people.set_once people.unset people.increment people.append people.union people.track_charge people.clear_charges people.delete_user people.remove".split(" ");
for(h=0;h<i.length;h++)g(a,i[h]);var j="set set_once union unset remove delete".split(" ");a.get_group=function(){function b(c){d[c]=function(){call2_args=arguments;call2=[c].concat(Array.prototype.slice.call(call2_args,0));a.push([e,call2])}}for(var d={},e=["get_group"].concat(Array.prototype.slice.call(arguments,0)),c=0;c<j.length;c++)b(j[c]);return d};b._i.push([e,f,c])};b.__SV=1.2;e=f.createElement("script");e.type="text/javascript";e.async=!0;e.crossOrigin="anonymous";e.src="undefined"!==typeof MIXPANEL_CUSTOM_LIB_URL?
MIXPANEL_CUSTOM_LIB_URL:"file:"===f.location.protocol&&"//cdn.mxpnl.com/libs/mixpanel-2-latest.min.js".match(/^\/\//)?"https://cdn.mxpnl.com/libs/mixpanel-2-latest.min.js":"//cdn.mxpnl.com/libs/mixpanel-2-latest.min.js";g=f.getElementsByTagName("script")[0];g.parentNode.insertBefore(e,g)}})(document,window.mixpanel||[]);
""";

void _runScript(String source) {
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final script =
      document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
  script.setProperty('textContent'.toJS, source.toJS);
  document
      .getProperty<JSObject>('head'.toJS)
      .callMethod('appendChild'.toJS, script);
}

/// Resolves once the CDN library has replaced the snippet stub. The stub
/// queues calls and has no `config`; the real instance does.
Future<void> _awaitLibrary() async {
  for (var attempt = 0; attempt < 300; attempt++) {
    final mixpanel = globalContext.getProperty<JSAny?>('mixpanel'.toJS);
    if (mixpanel != null &&
        mixpanel.typeofEquals('object') &&
        (mixpanel as JSObject).getProperty<JSAny?>('config'.toJS) != null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'mixpanel-js did not load from the CDN; this suite needs network access.',
  );
}

/// The captured request bodies, decoded from mixpanel-js's base64 `data` form.
List<Map<String, Object?>> _sentEvents() {
  final sent = globalContext.getProperty<JSArray<JSAny?>>('__mpSent'.toJS);
  return sent.toDart.map((body) {
    final raw = (body! as JSString).toDart;
    final data = RegExp(r'data=([^&]*)').firstMatch(raw)?.group(1);
    final json = data == null
        ? raw
        : utf8.decode(base64.decode(Uri.decodeComponent(data)));
    final decoded = jsonDecode(json);
    final event = decoded is List ? decoded.first : decoded;
    return (event as Map).cast<String, Object?>();
  }).toList();
}

void _clearSent() {
  globalContext.setProperty('__mpSent'.toJS, <Object?>[].jsify());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mixpanel_flutter');
  late Mixpanel mixpanel;

  setUpAll(() async {
    _runScript(_captureShim);
    _runScript(_loaderSnippet);

    final plugin = MixpanelFlutterPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, plugin.handleMethodCall);

    // Queues into the snippet stub, which the CDN library then drains.
    mixpanel = await Mixpanel.init(
      'event-bridge-test-token',
      trackAutomaticEvents: false,
      config: <String, dynamic>{
        'api_host': _apiHost,
        // Send on every track so a request is observable immediately.
        'batch_requests': false,
        // Keep the suite from writing cookies or localStorage.
        'persistence': 'memory',
      },
    );
    await _awaitLibrary();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  setUp(_clearSent);

  test('should deliver the tracked event to the bridge when a listener is '
      'subscribed', () async {
    final received = <MixpanelEvent>[];
    final subscription = MixpanelEventBridge.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    mixpanel.track('Checkout', properties: <String, dynamic>{'plan': 'pro'});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(received.map((event) => event.eventName), ['Checkout']);
    // mixpanel-js decorates properties before calling the hook, so the bridge
    // sees the same payload the event is sent with.
    expect(received.single.properties, containsPair('plan', 'pro'));
    expect(received.single.properties, containsPair('mp_lib', 'flutter'));
    expect(received.single.properties,
        containsPair('token', 'event-bridge-test-token'));

    await subscription.cancel();
  });

  test('should still send the event when the bridge forwards it', () async {
    final received = <MixpanelEvent>[];
    final subscription = MixpanelEventBridge.events.listen(received.add);
    await Future<void>.delayed(Duration.zero);

    mixpanel.track('Purchase', properties: <String, dynamic>{'seats': 3});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The hook is a transform: returning the wrong shape would make
    // mixpanel-js drop the event instead of sending it.
    final sent = _sentEvents();
    expect(sent, hasLength(1));
    expect(sent.single['event'], 'Purchase');
    expect(sent.single['properties'], containsPair('seats', 3));
    expect(received.map((event) => event.eventName), ['Purchase']);

    await subscription.cancel();
  });

  test('should still send the event when no listener is subscribed', () async {
    // The common case: apps that never read the bridge. The hook runs anyway,
    // so it must hand the event back untouched.
    mixpanel.track('Unobserved', properties: <String, dynamic>{'seats': 1});
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final sent = _sentEvents();
    expect(sent, hasLength(1));
    expect(sent.single['event'], 'Unobserved');
    expect(sent.single['properties'], containsPair('seats', 1));
  });
}
