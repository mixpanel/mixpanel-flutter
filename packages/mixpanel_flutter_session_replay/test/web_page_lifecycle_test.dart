@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/web_page_lifecycle.dart';
import 'package:web/web.dart' as web;

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
