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

  /// Get current active session (creates one if none exists)
  Session getCurrentSession() {
    _currentSession ??= startNewSession();
    return _currentSession!;
  }
}
