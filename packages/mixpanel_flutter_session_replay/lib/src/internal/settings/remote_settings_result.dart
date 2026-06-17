import 'sdk_config.dart';

/// Result from the remote settings endpoint, containing both recording status
/// and SDK config.
class RemoteSettingsResult {
  final bool isRecordingEnabled;
  final SdkConfig? sdkConfig;
  final bool isFromCache;

  const RemoteSettingsResult({
    required this.isRecordingEnabled,
    this.sdkConfig,
    required this.isFromCache,
  });
}
