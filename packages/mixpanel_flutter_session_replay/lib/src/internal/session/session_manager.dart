import 'package:clock/clock.dart';

import '../../models/session.dart';

/// Manages the current recording session lifecycle
class SessionManager {
  /// Current active session
  Session? _currentSession;

  SessionManager();

  /// Start a new recording session
  Session startNewSession() {
    _currentSession = Session(
      id: Session.generateId(),
      startTime: clock.now(),
      status: SessionStatus.active,
    );
    return _currentSession!;
  }

  /// Resume a session from persisted data (web page reload).
  ///
  /// Sets the current session without generating a new ID.
  /// Used when a valid non-expired session is found in IndexedDB on web init.
  Session resumeSession(Session session) {
    _currentSession = session;
    return _currentSession!;
  }

  /// Get current active session (creates one if none exists)
  Session getCurrentSession() {
    _currentSession ??= startNewSession();
    return _currentSession!;
  }
}
