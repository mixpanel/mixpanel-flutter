import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'autocapture_options.dart';
import 'click_event.dart';

/// Consent authorization is independent of navigation/detection cancellation.
enum CaptureStatus { suspended, enabled, closed }

/// One consent operation, spanning a native lifecycle call and its recovery read.
class ConsentRequest {
  ConsentRequest._();
  bool _cancelled = false;
}

/// Pending signals retain this session; invalidation cancels them as a group.
class CaptureSession {
  CaptureSession._();
  bool _active = true;
  bool get isActive => _active;
}

/// Analytics adapter boundary. No widget or native-channel dependencies.
/// Not an application API; kept separate for future package extraction.
class AutocaptureController extends ChangeNotifier {
  AutocaptureController(this.options, this._emit);
  final AutocaptureOptions options;
  final Future<void> Function(String name, ClickEvent event) _emit;
  CaptureStatus _status = CaptureStatus.suspended;
  ConsentRequest? _pendingConsent;
  CaptureSession _session = CaptureSession._();
  final Map<int, Object> _owners = {};

  CaptureStatus get status => _status;
  bool get allowed => _status == CaptureStatus.enabled && options.isEnabled;
  CaptureSession get session => _session;

  // One observer per native Flutter view for this analytics instance.
  bool claim(int viewId, Object owner) {
    if (_status == CaptureStatus.closed) return false;
    final current = _owners[viewId];
    if (current != null && !identical(current, owner)) return false;
    _owners[viewId] = owner;
    return true;
  }

  void release(int viewId, Object owner) {
    if (identical(_owners[viewId], owner)) _owners.remove(viewId);
  }

  ConsentRequest suspend() {
    _cancelConsent();
    final request = ConsentRequest._();
    if (_status == CaptureStatus.closed) {
      request._cancelled = true;
      return request;
    }
    _pendingConsent = request;
    _status = CaptureStatus.suspended;
    invalidate();
    return request;
  }

  /// Navigation cancels detections, but must not cancel a consent operation.
  void invalidate() {
    if (_status == CaptureStatus.closed) return;
    _session._active = false;
    _session = CaptureSession._();
    notifyListeners();
  }

  bool _isCurrent(ConsentRequest request) =>
      _status != CaptureStatus.closed &&
      !request._cancelled &&
      identical(_pendingConsent, request);

  void _cancelConsent() {
    _pendingConsent?._cancelled = true;
    _pendingConsent = null;
  }

  Future<void> refreshConsent(Future<bool?> Function() read,
      {ConsentRequest? request}) async {
    if (_status == CaptureStatus.closed ||
        (request != null && !_isCurrent(request))) {
      return;
    }
    // Replace the lifecycle request with a read request, consuming it once.
    final reading = suspend();
    if (!_isCurrent(reading)) return;
    bool? optedOut;
    try {
      optedOut = await read();
    } catch (_) {
      // Unknown consent never permits collection.
      developer.log(
          'Autocapture consent read failed; capture remains suspended.',
          name: 'Mixpanel');
    }
    if (!_isCurrent(reading)) return;
    _pendingConsent = null;
    _status =
        optedOut == false ? CaptureStatus.enabled : CaptureStatus.suspended;
    notifyListeners();
  }

  void emit(String name, ClickEvent event, CaptureSession session) {
    if (!allowed || !session.isActive || !identical(session, _session)) return;
    // Invoke immediately so a later identify cannot relabel a deferred event.
    try {
      unawaited(_emit(name, event).catchError((Object _) {}));
    } catch (_) {
      // Capture must never affect delivery of the app's own input event.
    }
  }

  void close() {
    if (_status == CaptureStatus.closed) return;
    _cancelConsent();
    _session._active = false;
    _status = CaptureStatus.closed;
    _owners.clear();
    notifyListeners();
    // Mounted widgets still remove their listeners when detached.
  }
}
