/// A tracked Mixpanel event broadcast through [MixpanelEventBridge].
class MixpanelEvent {
  const MixpanelEvent({required this.eventName, this.properties});

  /// The name of the tracked event, exactly as `mixpanel_flutter` emitted it.
  final String eventName;

  /// The fully-decorated event properties: user-supplied props merged with
  /// super properties and automatic properties (`$os`, `$app_version`,
  /// `$city`, etc.).
  ///
  /// Nullable because the Android upstream may pass through a null property
  /// payload; the iOS upstream always supplies a (possibly empty) map.
  /// Consumers should null-check.
  final Map<String, Object?>? properties;

  @override
  String toString() => 'MixpanelEvent($eventName, $properties)';
}
