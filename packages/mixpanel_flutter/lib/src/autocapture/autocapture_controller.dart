import 'dart:async';
import 'package:flutter/foundation.dart';
import 'autocapture_options.dart';
import 'click_event.dart';

/// Analytics adapter boundary. No widget or native-channel dependencies.
/// Not an application API; kept separate for future package extraction.
class AutocaptureController extends ChangeNotifier {
  AutocaptureController(this.options, this._emit);
  final AutocaptureOptions options;
  final Future<void> Function(String name, ClickEvent event) _emit;
  bool _allowed = false;
  bool _closed = false;
  int _generation = 0;
  final Map<int, Object> _owners = {};

  bool get allowed => !_closed && _allowed && options.isEnabled;
  int get generation => _generation;

  // One observer per native Flutter view for this analytics instance.
  bool claim(int viewId, Object owner) {
    if (_closed) return false;
    final current = _owners[viewId];
    if (current != null && !identical(current, owner)) return false;
    _owners[viewId] = owner;
    return true;
  }

  void release(int viewId, Object owner) {
    if (identical(_owners[viewId], owner)) _owners.remove(viewId);
  }

  int suspend() {
    _allowed = false;
    invalidate();
    return _generation;
  }

  /// Navigation/identity/lifecycle invalidation drops in-flight detections.
  void invalidate() {
    if (_closed) return;
    _generation++;
    notifyListeners();
  }

  Future<void> refreshConsent(Future<bool?> Function() read,
      {int? generation}) async {
    if (_closed || (generation != null && generation != _generation)) return;
    final expected = suspend();
    bool? optedOut;
    try {
      optedOut = await read();
    } catch (_) {
      // Unknown consent never permits collection.
    }
    if (_closed || expected != _generation) return;
    _allowed = optedOut == false;
    notifyListeners();
  }

  void emit(String name, ClickEvent event, int generation) {
    if (!allowed || generation != _generation) return;
    // Invoke immediately so a later identify cannot relabel a deferred event.
    try {
      unawaited(_emit(name, event).catchError((Object _) {}));
    } catch (_) {
      // Capture must never affect delivery of the app's own input event.
    }
  }

  void close() {
    if (_closed) return;
    suspend();
    _closed = true;
    _owners.clear();
    // Mounted widgets still remove their listeners when detached.
  }
}
