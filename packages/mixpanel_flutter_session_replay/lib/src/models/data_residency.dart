/// Base URLs for Mixpanel data residency regions.
///
/// Pass one of these constants (or a custom URL) to
/// [SessionReplayOptions.serverUrl] to send session replay data to the
/// matching region.
///
/// Example:
/// ```dart
/// SessionReplayOptions(serverUrl: DataResidency.eu)
/// ```
abstract final class DataResidency {
  /// Base URL for US data residency (default).
  static const String us = 'https://api.mixpanel.com';

  /// Base URL for EU data residency.
  static const String eu = 'https://api-eu.mixpanel.com';

  /// Base URL for India data residency.
  static const String india = 'https://api-in.mixpanel.com';
}
