import 'package:flutter/services.dart';

/// Requests extended background execution time from the platform.
///
/// On iOS, this calls UIApplication.beginBackgroundTask() which grants ~30 seconds
/// of execution time after the app enters background. This prevents the OS from
/// suspending the process before a flush completes.
///
/// On all other platforms (Android, macOS, Linux, Windows, Web), this is a no-op
/// since they don't aggressively suspend background processes.
class BackgroundTaskManager {
  static const _channel = MethodChannel('com.mixpanel.flutter_session_replay');

  /// Request extended background execution time.
  ///
  /// Call this before starting work that must complete in the background.
  /// Returns immediately on platforms that don't need it.
  Future<void> beginBackgroundTask() async {
    try {
      await _channel.invokeMethod<void>('beginBackgroundTask');
    } catch (_) {
      // Best-effort — if platform doesn't support it, continue without extension
    }
  }

  /// Signal that background work is complete.
  ///
  /// Call this when the flush finishes to release the background task.
  /// Must be called after [beginBackgroundTask] to avoid system penalties.
  Future<void> endBackgroundTask() async {
    try {
      await _channel.invokeMethod<void>('endBackgroundTask');
    } catch (_) {
      // Best-effort cleanup
    }
  }
}
