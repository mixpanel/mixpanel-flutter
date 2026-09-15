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
  ownerId: _tabOwnerId(token),
);

String _tabOwnerId(String token) {
  final key = 'mp_sr_tab_${token.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
  try {
    final existing = web.window.sessionStorage.getItem(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    web.window.sessionStorage.setItem(key, created);
    return created;
  } catch (_) {
    return const Uuid().v4();
  }
}
