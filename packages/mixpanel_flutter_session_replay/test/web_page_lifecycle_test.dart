@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_page_lifecycle.dart';
import 'package:web/web.dart' as web;

/// Shadows `document.visibilityState` with a fixed value for one test.
void _fakeVisibilityState(String state) {
  final object = globalContext['Object'] as JSObject;
  object.callMethod(
    'defineProperty'.toJS,
    web.document,
    'visibilityState'.toJS,
    <String, Object?>{
      'get': (() => state.toJS).toJS,
      'configurable': true,
    }.jsify(),
  );
  addTearDown(() => web.document.delete('visibilityState'.toJS));
}

void main() {
  test('reports pagehide and pageshow browser lifecycle signals', () {
    var hiddenCount = 0;
    var visibleCount = 0;
    final registration = registerWebPageLifecycle(
      onHidden: () => hiddenCount++,
      onVisible: () => visibleCount++,
    )!;
    addTearDown(registration);

    web.window.dispatchEvent(web.Event('pagehide'));
    web.window.dispatchEvent(web.Event('pageshow'));

    expect(hiddenCount, 1);
    expect(visibleCount, 1);
  });

  test('reports back-forward-cache page transitions', () {
    var hiddenCount = 0;
    var visibleCount = 0;
    final registration = registerWebPageLifecycle(
      onHidden: () => hiddenCount++,
      onVisible: () => visibleCount++,
    )!;
    addTearDown(registration);

    web.window.dispatchEvent(
      web.PageTransitionEvent(
        'pagehide',
        web.PageTransitionEventInit(persisted: true),
      ),
    );
    web.window.dispatchEvent(
      web.PageTransitionEvent(
        'pageshow',
        web.PageTransitionEventInit(persisted: true),
      ),
    );

    expect(hiddenCount, 1);
    expect(visibleCount, 1);
  });

  test('does not report pageshow while the document is hidden', () {
    // GIVEN a background tab or prerendered page receiving pageshow
    _fakeVisibilityState('hidden');
    var visibleCount = 0;
    final registration = registerWebPageLifecycle(
      onHidden: () {},
      onVisible: () => visibleCount++,
    )!;
    addTearDown(registration);

    // WHEN
    web.window.dispatchEvent(web.Event('pageshow'));

    // THEN the page is not treated as foregrounded; visibilitychange will
    // report it once it is actually shown
    expect(visibleCount, 0);
  });

  test('removes browser lifecycle listeners when disposed', () {
    var hiddenCount = 0;
    final registration = registerWebPageLifecycle(
      onHidden: () => hiddenCount++,
      onVisible: () {},
    )!;
    registration();

    web.window.dispatchEvent(web.Event('pagehide'));

    expect(hiddenCount, 0);
  });
}
