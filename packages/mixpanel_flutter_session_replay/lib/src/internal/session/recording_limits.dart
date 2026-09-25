import '../logger.dart';

/// Longest window any replay timeout may request.
///
/// Matches mixpanel-js's `MAX_RECORDING_MS`. It also keeps timers well below
/// the browser `setTimeout` ceiling of 2^31-1 ms, beyond which browsers fire
/// the callback immediately instead of after the requested delay.
const maxRecordingDuration = Duration(hours: 24);

/// Caps [value] at [maxRecordingDuration], logging when it had to be lowered.
Duration capRecordingDuration(
  Duration value, {
  required String name,
  required MixpanelLogger logger,
}) {
  if (value <= maxRecordingDuration) return value;
  logger.warning(
    '$name cannot be greater than ${maxRecordingDuration.inMilliseconds}ms. '
    'Capping value.',
  );
  return maxRecordingDuration;
}
