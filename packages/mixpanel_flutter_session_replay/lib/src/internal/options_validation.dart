import '../models/configuration.dart';
import '../session_replay_options.dart';
import 'logger.dart';
import 'session/recording_limits.dart';

/// Throws [ArgumentError] when [token] or [options] cannot initialize the SDK.
///
/// These checks run at initialization rather than as constructor assertions:
/// the options classes are `const`, and `Duration` comparisons are not
/// constant expressions.
void validateOptions(String token, SessionReplayOptions options) {
  if (token.isEmpty) {
    throw ArgumentError('token cannot be empty');
  }

  if (options.autoRecordSessionsPercent < 0 ||
      options.autoRecordSessionsPercent > 100) {
    throw ArgumentError('autoRecordSessionsPercent must be between 0 and 100');
  }

  if (options.storageQuotaMB <= 0) {
    throw ArgumentError('storageQuotaMB must be positive');
  }

  final platformOptions = options.platformOptions;
  if (platformOptions.web.idleTimeout < Duration.zero) {
    throw ArgumentError('web idleTimeout cannot be negative');
  }

  _requirePositivePause(platformOptions.mobile.onBackground, 'mobile');

  if (platformOptions.web.maxSessionDuration <= Duration.zero) {
    throw ArgumentError('web maxSessionDuration must be positive');
  }
}

void _requirePositivePause(ReplayBackgroundBehavior behavior, String platform) {
  if (behavior case ReplayBackgroundPauseBehavior(
    :final idleTimeout,
  ) when idleTimeout <= Duration.zero) {
    throw ArgumentError(
      '$platform background pause idleTimeout must be positive',
    );
  }
}

/// Returns [options] with every duration capped at [maxRecordingDuration],
/// logging any value that had to be lowered.
///
/// Both platforms' options are capped; each platform's initialization reads
/// only its own.
PlatformOptions capPlatformOptions(
  PlatformOptions options,
  MixpanelLogger logger,
) => PlatformOptions(
  mobile: MobileOptions(
    wifiOnly: options.mobile.wifiOnly,
    onBackground: _capBackgroundBehavior(
      options.mobile.onBackground,
      name: 'mobile background pause idleTimeout',
      logger: logger,
    ),
  ),
  web: WebOptions(
    idleTimeout: capRecordingDuration(
      options.web.idleTimeout,
      name: 'web idleTimeout',
      logger: logger,
    ),
    maxSessionDuration: capRecordingDuration(
      options.web.maxSessionDuration,
      name: 'web maxSessionDuration',
      logger: logger,
    ),
  ),
);

ReplayBackgroundBehavior _capBackgroundBehavior(
  ReplayBackgroundBehavior behavior, {
  required String name,
  required MixpanelLogger logger,
}) => switch (behavior) {
  ReplayBackgroundPauseBehavior(:final idleTimeout)
      when idleTimeout > maxRecordingDuration =>
    ReplayBackgroundBehavior.pause(
      idleTimeout: capRecordingDuration(
        idleTimeout,
        name: name,
        logger: logger,
      ),
    ),
  _ => behavior,
};
