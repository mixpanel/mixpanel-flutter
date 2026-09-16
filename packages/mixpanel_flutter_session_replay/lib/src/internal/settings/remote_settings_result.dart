import 'sdk_config.dart';

/// Result from the remote settings endpoint, containing both recording status
/// and SDK config.
class RemoteSettingsResult {
  final bool isRecordingEnabled;
  final SdkConfig? sdkConfig;
  final bool isFromCache;

  /// Server-side kill switch for wireframe capture.
  ///
  /// Defaults to enabled: the `wireframe` field is only requested (and only
  /// returned) when the app opted in to wireframes, and anything short of an
  /// explicit `false` leaves capture alone.
  final bool isWireframeEnabled;

  const RemoteSettingsResult({
    required this.isRecordingEnabled,
    this.sdkConfig,
    required this.isFromCache,
    this.isWireframeEnabled = true,
  });
}
