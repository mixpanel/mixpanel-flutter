/// A tracked Mixpanel event broadcast through [MixpanelEventBridge].
///
/// Shape mirrors the native common modules:
/// - Android `com.mixpanel.android.eventbridge.MixpanelEvent` (Kotlin)
/// - Swift `MixpanelSwiftCommon.MixpanelEvent`
///
/// [properties] is nullable to match Android's `JSONObject?`. On iOS the
/// native bridge always supplies a (possibly empty) dictionary, but
/// consumers should be prepared for null to preserve cross-platform parity.
class MixpanelEvent {
  const MixpanelEvent({required this.eventName, this.properties});

  /// The name of the tracked event, exactly as the native SDK emitted it.
  final String eventName;

  /// The fully-decorated event properties: user-supplied props merged with
  /// the native SDK's super properties and automatic properties (`$os`,
  /// `$app_version`, `$city`, etc.). May be null when no properties were
  /// attached on Android.
  final Map<String, Object?>? properties;

  @override
  String toString() => 'MixpanelEvent($eventName, $properties)';
}
