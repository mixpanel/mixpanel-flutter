@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/event_queue_factory_web.dart';
import 'package:web/web.dart' as web;

void main() {
  final storage = web.window.sessionStorage;
  String idKey(String token) => 'mp_sr_tab_$token';
  String liveKey(String token) => 'mp_sr_tab_live_$token';

  tearDown(() => storage.clear());

  group('resolveTabOwnerId', () {
    test('creates an ID and marks it live on a fresh tab', () {
      // GIVEN no stored tab state
      const token = 'fresh_tab';

      // WHEN the tab ID is resolved
      final ownerId = resolveTabOwnerId(token);

      // THEN it is stored and flagged as held by a live page
      expect(storage.getItem(idKey(token)), ownerId);
      expect(storage.getItem(liveKey(token)), '1');
    });

    test('reuses the stored ID after a reload', () {
      // GIVEN an ID whose page cleared its live flag while unloading
      const token = 'reloaded_tab';
      storage.setItem(idKey(token), 'previous-id');

      // WHEN the reloaded page resolves its tab ID
      final ownerId = resolveTabOwnerId(token);

      // THEN the same tab keeps its ID, so its replay can resume
      expect(ownerId, 'previous-id');
    });

    test('creates a new ID for storage copied from a live tab', () {
      // GIVEN storage duplicated from a tab that is still open
      const token = 'duplicated_tab';
      storage.setItem(idKey(token), 'original-id');
      storage.setItem(liveKey(token), '1');

      // WHEN the duplicate resolves its tab ID
      final ownerId = resolveTabOwnerId(token);

      // THEN it gets its own ID and cannot resume the original's replay
      expect(ownerId, isNot('original-id'));
      expect(storage.getItem(idKey(token)), ownerId);
    });

    test('keeps its ID when the SDK is initialized again in the same page', () {
      // GIVEN an ID already resolved by this page
      const token = 'reinitialized_tab';
      final first = resolveTabOwnerId(token);

      // WHEN it is resolved again while the live flag is set
      final second = resolveTabOwnerId(token);

      // THEN the page's own flag is not mistaken for a copied one
      expect(second, first);
    });

    test('clears the live flag on pagehide and restores it from bfcache', () {
      // GIVEN a live tab
      const token = 'lifecycle_tab';
      resolveTabOwnerId(token);

      // WHEN the page is hidden for unload
      web.window.dispatchEvent(web.Event('pagehide'));

      // THEN a reload of this tab may reuse its ID
      expect(storage.getItem(liveKey(token)), isNull);

      // WHEN the page is restored from the back/forward cache
      web.window.dispatchEvent(
        web.PageTransitionEvent(
          'pageshow',
          web.PageTransitionEventInit(persisted: true),
        ),
      );

      // THEN it is marked live again
      expect(storage.getItem(liveKey(token)), '1');
    });
  });
}
