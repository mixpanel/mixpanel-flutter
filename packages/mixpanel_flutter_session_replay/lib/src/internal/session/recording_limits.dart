import '../logger.dart';

/// Longest window any replay timeout may request.
///
/// Matches mixpanel-js's `MAX_RECORDING_MS`. It also keeps timers well below
/// the browser `setTimeout` ceiling of 2^31-1 ms, beyond which browsers fire
/// the callback immediately instead of after the requested delay.
const maxRecordingDuration = Duration(hours: 24);

/// How long an activity-driven deadline write may be held back.
///
/// User input refreshes the in-memory idle deadline at once but reaches
/// storage at most this often. Anything that reads the stored deadline of a
/// replay another runtime is recording must allow for this much lag.
const expiryWriteDebounce = Duration(seconds: 5);

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
