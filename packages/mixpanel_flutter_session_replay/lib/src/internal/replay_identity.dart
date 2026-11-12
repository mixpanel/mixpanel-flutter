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

  /// Whether a request names its user with `distinct_id`. Not when the
  /// identity has both a user and a company: Mixpanel builds the user from
  /// `$user_id` and `$company_id`, as it does for events, which carry no
  /// `distinct_id` either.
  static bool sendsDistinctId(MixpanelIdentity? identity) =>
      _nonEmpty(identity?.userId) == null ||
      _nonEmpty(identity?.companyId) == null;

  /// The identity keys Mixpanel resolves a replay's user from.
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

  /// Starts a stored distinct id that carries an identity. Control
  /// characters don't occur in real distinct ids, so a plain distinct id
  /// never starts with it. Not NUL: sqflite on iOS and macOS binds text as a C
  /// string, which would cut the value off at a NUL.
  static const String _storedIdentityPrefix = '\u0001mpid:';

  /// What the queue stores in its `distinct_id` column: [distinctId] itself
  /// when there's no [identity], otherwise both encoded behind a marker. Equal
  /// identities store the same text, so the queue can compare them in SQL.
  static String storedDistinctId(
    String distinctId,
    MixpanelIdentity? identity,
  ) {
    if (identity == null) return distinctId;
    return _storedIdentityPrefix +
        jsonEncode({
          'distinct_id': distinctId,
          'identity': normalize(identity).toMap(),
        });
  }

  /// The distinct id and identity a [storedDistinctId] value was made from.
  static (String, MixpanelIdentity?) fromStoredDistinctId(String stored) {
    if (!stored.startsWith(_storedIdentityPrefix)) return (stored, null);
    try {
      final decoded =
          jsonDecode(stored.substring(_storedIdentityPrefix.length))
              as Map<String, dynamic>;
      return (
        decoded['distinct_id'] as String,
        MixpanelIdentity.fromMap(decoded['identity'] as Map<String, dynamic>),
      );
    } catch (_) {
      return (stored, null);
    }
  }

  static String? _nonEmpty(String? value) =>
      value != null && value.isNotEmpty ? value : null;
}
