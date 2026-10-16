import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../models/configuration.dart';

/// How a replay responds to the app or page leaving and re-entering the
/// foreground.
///
/// Platform initialization picks the policy, so the coordinator follows it
/// instead of inferring the platform from which options happen to be set.
sealed class ReplayLifecyclePolicy {
  const ReplayLifecyclePolicy();

  /// The native policy for the configured [MobileOptions.onBackground].
  factory ReplayLifecyclePolicy.fromBackgroundBehavior(
    ReplayBackgroundBehavior behavior,
  ) => switch (behavior) {
    ReplayBackgroundPauseBehavior(:final idleTimeout) => PauseOnBackground(
      idleTimeout: idleTimeout,
    ),
    ReplayBackgroundStopBehavior() => stopOnBackground,
  };

  /// See [StopOnBackground].
  static const stopOnBackground = StopOnBackground();

  /// See [RecordThroughBackground].
  static const recordThroughBackground = RecordThroughBackground();

  /// Whether a return to the foreground with no replay recording applies the
  /// auto-record sampling decision again.
  ///
  /// The first foreground always applies it. After that, only a policy where
  /// leaving the foreground can end the replay makes each return a new
  /// sampling opportunity, as in the iOS and Android SDKs.
  bool get resamplesOnForeground;

  /// Whether [AppLifecycleState.inactive] counts as leaving the foreground.
  ///
  /// On native, inactive is the first step of backgrounding. On web it only
  /// means the window lost focus while the page may still be visible (an
  /// iframe, the address bar, devtools, another window), and mixpanel-js
  /// keeps recording through it, so web waits for the page to be hidden.
  bool get leavesForegroundWhenInactive;
}

/// Ends the replay when the app leaves the foreground. Each return starts a
/// new replay with a fresh sampling decision. The native default.
final class StopOnBackground extends ReplayLifecyclePolicy {
  const StopOnBackground();

  @override
  bool get resamplesOnForeground => true;

  @override
  bool get leavesForegroundWhenInactive => true;
}

/// Retains the replay while the app is in the background, for up to
/// [idleTimeout]. A return after that starts a new replay with a fresh
/// sampling decision.
final class PauseOnBackground extends ReplayLifecyclePolicy {
  const PauseOnBackground({required this.idleTimeout});

  /// How long the replay may stay paused before it is replaced.
  final Duration idleTimeout;

  @override
  bool get resamplesOnForeground => true;

  @override
  bool get leavesForegroundWhenInactive => true;
}

/// Keeps recording while the page is hidden, as mixpanel-js does. Visibility
/// is not a replay boundary, so auto-record is sampled once per page load, and
/// a stopped or sampled-out page stays that way across tab switches.
final class RecordThroughBackground extends ReplayLifecyclePolicy {
  const RecordThroughBackground();

  @override
  bool get resamplesOnForeground => false;

  @override
  bool get leavesForegroundWhenInactive => false;
}
