/// Names who events, profile updates and replays belong to.
///
/// Shared by `mixpanel_flutter` and `mixpanel_flutter_session_replay`, so the
/// identity analytics reports can be passed to Session Replay as is.
///
/// On a project that uses hierarchical groups (see the `hierarchicalGroups`
/// option of `Mixpanel.init`), Mixpanel builds the user's distinct id from
/// `$company_id` and `$user_id`, so the company is part of the user's identity:
/// the same user id in two companies is two users. Other projects ignore
/// [companyId].
///
/// ```dart
/// await mixpanel.identifyWithIdentity(
///     MixpanelIdentity(userId: 'user_123', companyId: 'acme'));
/// ```
///
/// Instances are immutable and compare by value.
class MixpanelIdentity {
  /// The user's id. On a hierarchical groups project it only needs to be
  /// unique within the company.
  final String? userId;

  /// The id of the user's top-level company, on a hierarchical groups project.
  final String? companyId;

  /// The device id the SDK assigned. It is reported by
  /// `Mixpanel.getIdentity` and ignored when identifying, because the SDK
  /// owns the device id.
  final String? deviceId;

  /// Creates an identity for a user and, on a hierarchical groups project,
  /// their company.
  const MixpanelIdentity({required this.userId, this.companyId})
      : deviceId = null;

  /// For internal use by the Mixpanel SDKs only, which own the device id. Apps
  /// create an identity with the unnamed constructor.
  const MixpanelIdentity.withDeviceId(
      {required this.userId, this.companyId, this.deviceId});

  /// Creates a MixpanelIdentity from a Map (used for platform channel deserialization).
  factory MixpanelIdentity.fromMap(Map<dynamic, dynamic>? map) {
    return MixpanelIdentity.withDeviceId(
      userId: map?['userId'] as String?,
      companyId: map?['companyId'] as String?,
      deviceId: map?['deviceId'] as String?,
    );
  }

  /// Converts this identity to a Map for serialization.
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'companyId': companyId,
      'deviceId': deviceId,
    };
  }

  @override
  String toString() {
    final parts = <String>[
      if (userId != null) 'userId=$userId',
      if (companyId != null) 'companyId=$companyId',
      if (deviceId != null) 'deviceId=$deviceId',
    ];
    return 'MixpanelIdentity(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MixpanelIdentity &&
        userId == other.userId &&
        companyId == other.companyId &&
        deviceId == other.deviceId;
  }

  @override
  int get hashCode {
    var result = 17;
    result = 37 * result + (userId?.hashCode ?? 0);
    result = 37 * result + (companyId?.hashCode ?? 0);
    result = 37 * result + (deviceId?.hashCode ?? 0);
    return result;
  }
}
