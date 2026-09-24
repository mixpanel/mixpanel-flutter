import 'dart:js_interop';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;

import 'event_queue_interface.dart';
import 'indexed_db_event_queue.dart';
import '../logger.dart';

EventQueue createWebEventQueue({
  required String token,
  required int quotaMB,
  required MixpanelLogger logger,
}) => IndexedDbEventQueue(
  token: token,
  quotaMB: quotaMB,
  logger: logger,
  ownerId: resolveTabOwnerId(token),
);

/// IDs resolved by this page, so re-initializing the SDK for the same token
/// keeps its ID instead of mistaking its own live flag for a copied one.
final _resolvedOwnerIds = <String, String>{};

/// Returns an ID unique to this browser tab that survives reloads.
///
/// The ID lives in `sessionStorage`, which browsers copy into a tab created by
/// "Duplicate tab" or `window.open`. Like mixpanel-js, a second key marks the
/// ID as held by a live page: it is set on load and removed when the page is
/// hidden for unload. Finding the flag on load means the storage was copied
/// from a tab that is still open, so a new ID is generated rather than both
/// tabs resuming the same replay.
@visibleForTesting
String resolveTabOwnerId(String token) =>
    _resolvedOwnerIds[token] ??= _readOrCreateTabOwnerId(token);

String _readOrCreateTabOwnerId(String token) {
  final suffix = token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final idKey = 'mp_sr_tab_$suffix';
  final liveKey = 'mp_sr_tab_live_$suffix';
  try {
    final storage = web.window.sessionStorage;
    final existing = storage.getItem(idKey);
    final copiedFromLiveTab = storage.getItem(liveKey) != null;
    final String ownerId;
    if (existing == null || existing.isEmpty || copiedFromLiveTab) {
      ownerId = const Uuid().v4();
      storage.setItem(idKey, ownerId);
    } else {
      ownerId = existing;
    }
    storage.setItem(liveKey, '1');
    _listenForPageUnload(liveKey);
    return ownerId;
  } catch (_) {
    return const Uuid().v4();
  }
}

/// Clears the live flag when the page may be unloading, and restores it if the
/// page comes back from the back/forward cache.
///
/// mixpanel-js uses `beforeunload`. `pagehide` also fires on mobile Safari
/// and when a page enters the back/forward cache, where `beforeunload` does
/// not, so the flag is restored on `pageshow` for a page that was kept alive.
void _listenForPageUnload(String liveKey) {
  web.window.addEventListener(
    'pagehide',
    ((web.Event _) {
      try {
        web.window.sessionStorage.removeItem(liveKey);
      } catch (_) {}
    }).toJS,
  );
  web.window.addEventListener(
    'pageshow',
    ((web.PageTransitionEvent event) {
      if (!event.persisted) return;
      try {
        web.window.sessionStorage.setItem(liveKey, '1');
      } catch (_) {}
    }).toJS,
  );
}
