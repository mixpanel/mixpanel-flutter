import 'package:test/test.dart';
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';

void main() {
  group('MixpanelIdentity', () {
    test('company and device default to null', () {
      const identity = MixpanelIdentity(userId: 'user_123');
      expect(identity.userId, 'user_123');
      expect(identity.companyId, isNull);
      expect(identity.deviceId, isNull);
    });

    test('the unnamed constructor never sets a device id', () {
      const identity = MixpanelIdentity(userId: 'user_123', companyId: 'acme');
      expect(identity.deviceId, isNull);
    });

    test('equality covers every value', () {
      const identity = MixpanelIdentity.withDeviceId(
        userId: 'user_123',
        companyId: 'acme',
        deviceId: 'device_abc',
      );
      expect(
        identity,
        const MixpanelIdentity.withDeviceId(
          userId: 'user_123',
          companyId: 'acme',
          deviceId: 'device_abc',
        ),
      );
      expect(
        identity.hashCode,
        const MixpanelIdentity.withDeviceId(
          userId: 'user_123',
          companyId: 'acme',
          deviceId: 'device_abc',
        ).hashCode,
      );
      expect(
        identity,
        isNot(const MixpanelIdentity(userId: 'user_123', companyId: 'acme')),
      );
      expect(
        identity,
        isNot(
          const MixpanelIdentity.withDeviceId(
            userId: 'user_123',
            companyId: 'globex',
            deviceId: 'device_abc',
          ),
        ),
      );
    });

    test('round-trips through a map', () {
      const identity = MixpanelIdentity.withDeviceId(
        userId: 'user_123',
        companyId: 'acme',
        deviceId: 'device_abc',
      );
      expect(identity.toMap(), {
        'userId': 'user_123',
        'companyId': 'acme',
        'deviceId': 'device_abc',
      });
      expect(MixpanelIdentity.fromMap(identity.toMap()), identity);
    });

    test('fromMap treats missing values and a null map as unset', () {
      expect(
        MixpanelIdentity.fromMap({'deviceId': 'device_abc'}),
        const MixpanelIdentity.withDeviceId(
          userId: null,
          deviceId: 'device_abc',
        ),
      );
      expect(
        MixpanelIdentity.fromMap(null),
        const MixpanelIdentity(userId: null),
      );
    });

    test('toString omits unset values', () {
      expect(
        const MixpanelIdentity.withDeviceId(
          userId: 'user_123',
          companyId: 'acme',
          deviceId: 'device_abc',
        ).toString(),
        'MixpanelIdentity(userId=user_123, companyId=acme, deviceId=device_abc)',
      );
      expect(
        const MixpanelIdentity(userId: 'user_123').toString(),
        'MixpanelIdentity(userId=user_123)',
      );
      expect(
        const MixpanelIdentity.withDeviceId(
          userId: null,
          deviceId: 'device_abc',
        ).toString(),
        'MixpanelIdentity(deviceId=device_abc)',
      );
    });
  });
}
