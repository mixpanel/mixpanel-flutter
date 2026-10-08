/// Decides what a pause or stop means for captures already in flight.
///
/// A capture takes a [CaptureTicket] when it begins. Stopping or pausing
/// recording cancels acquisition for every earlier ticket, so a frame still
/// waiting on the browser never reads the pixels of whatever is shown next.
/// A pause additionally discards frames that were already acquired: the
/// replay is retained and such a frame would cross the pause boundary. A stop
/// keeps them, pinned to the replay they were captured for, as the native
/// SDKs do.
class CaptureInvalidation {
  int _epoch = 0;
  int _lastPauseEpoch = -1;

  /// Marks the start of a capture.
  CaptureTicket begin() => CaptureTicket._(_epoch);

  /// Recording stopped: pending acquisitions are cancelled, acquired frames
  /// are kept.
  void noteStop() => _epoch++;

  /// Recording paused: pending acquisitions are cancelled and acquired frames
  /// are discarded.
  void notePause() {
    _epoch++;
    _lastPauseEpoch = _epoch;
  }

  /// Whether a capture holding [ticket] must not acquire pixels any more.
  bool isCancelled(CaptureTicket ticket) => ticket._epoch != _epoch;

  /// Whether a frame acquired under [ticket] must be dropped.
  bool discardsAcquired(CaptureTicket ticket) =>
      _lastPauseEpoch > ticket._epoch;
}

/// Identifies one in-flight capture. See [CaptureInvalidation].
class CaptureTicket {
  const CaptureTicket._(this._epoch);

  final int _epoch;
}
