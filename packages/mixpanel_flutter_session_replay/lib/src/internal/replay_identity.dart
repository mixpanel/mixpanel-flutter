import 'dart:convert';

import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

/// How a [MixpanelIdentity] reaches the record endpoint. Empty values are
/// treated as unset, so a replay never sends a key that would resolve to a
/// different user than the app's events.
class ReplayIdentity {
  ReplayIdentity._();

  /// The identity with empty values unset, so two spellings of "absent"
  /// compare and store the same.
  static MixpanelIdentity normalize(MixpanelIdentity identity) =>
      MixpanelIdentity.withDeviceId(
        userId: _nonEmpty(identity.userId),
        companyId: _nonEmpty(identity.companyId),
        deviceId: _nonEmpty(identity.deviceId),
      );

  /// The distinct id analytics sends on events for this identity: the user
  /// once identified, otherwise `$device:` and the device id. Null when the
  /// identity names neither.
  static String? distinctId(MixpanelIdentity identity) {
    final userId = _nonEmpty(identity.userId);
    if (userId != null) return userId;
    final deviceId = _nonEmpty(identity.deviceId);
    return deviceId != null ? '\$device:$deviceId' : null;
  }

  /// The identity keys Mixpanel resolves a replay's user from, alongside
  /// `distinct_id`.
  static Map<String, String> queryParams(MixpanelIdentity? identity) {
    if (identity == null) return const {};
    final userId = _nonEmpty(identity.userId);
    final companyId = _nonEmpty(identity.companyId);
    final deviceId = _nonEmpty(identity.deviceId);
    return {
      '\$user_id': ?userId,
      '\$company_id': ?companyId,
      '\$device_id': ?deviceId,
    };
  }

  /// The stored form of [identity]: equal identities encode to the same text,
  /// so the queue can compare them in SQL.
  static String? encode(MixpanelIdentity? identity) =>
      identity == null ? null : jsonEncode(normalize(identity).toMap());

  static MixpanelIdentity? decode(String? stored) => stored == null
      ? null
      : MixpanelIdentity.fromMap(jsonDecode(stored) as Map<String, dynamic>);

  static String? _nonEmpty(String? value) =>
      value != null && value.isNotEmpty ? value : null;
}
