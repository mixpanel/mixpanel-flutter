/// Remote enablement state for session replay recording.
enum RemoteEnablementState {
  /// Enablement check has not been performed yet
  pending,

  /// Enablement check completed - recording is allowed
  enabled,

  /// Enablement check completed - recording is disabled
  disabled,
}
