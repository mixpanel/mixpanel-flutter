import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/codec/mixpanel_message_codec.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

void main() {
  const MethodChannel channel = MethodChannel(
      'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));
  MethodCall? methodCall;
  late Mixpanel _mixpanel;

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Methods handling', () {
    setUp(() async {
      channel.setMockMethodCallHandler((MethodCall m) async {
        methodCall = m;
      });

      _mixpanel =
          await Mixpanel.init("test token", optOutTrackingDefault: false, trackAutomaticEvents: true);
    });

    tearDown(() {
      channel.setMockMethodCallHandler(null);
      methodCall = null;
    });

    test('check initialize call', () async {
      _mixpanel =
          await Mixpanel.init("test token", optOutTrackingDefault: false, trackAutomaticEvents: true);
      expect(
        methodCall,
        isMethodCall(
          'initialize',
          arguments: <String, dynamic>{
            'token': "test token",
            'optOutTrackingDefault': false,
            'trackAutomaticEvents': true,
            'mixpanelProperties': {
              '\$lib_version': '2.1.1',
              'mp_lib': 'flutter',
            },
            'superProperties': null,
            'config': null,
          },
        ),
      );
    });

    test('check initialize call with optOutTracking true', () async {
      _mixpanel =
          await Mixpanel.init("test token", optOutTrackingDefault: true, trackAutomaticEvents: true);
      expect(
        methodCall,
        isMethodCall(
          'initialize',
          arguments: <String, dynamic>{
            'token': "test token",
            'optOutTrackingDefault': true,
            'trackAutomaticEvents': true,
            'mixpanelProperties': {
              '\$lib_version': '2.1.1',
              'mp_lib': 'flutter',
            },
            'superProperties': null,
            'config': null,
          },
        ),
      );
    });

    test('check initialize call with trackAutomaticEvents false', () async {
      _mixpanel =
      await Mixpanel.init("test token", optOutTrackingDefault: true, trackAutomaticEvents: false);
      expect(
        methodCall,
        isMethodCall(
          'initialize',
          arguments: <String, dynamic>{
            'token': "test token",
            'optOutTrackingDefault': true,
            'trackAutomaticEvents': false,
            'mixpanelProperties': {
              '\$lib_version': '2.1.1',
              'mp_lib': 'flutter',
            },
            'superProperties': null,
            'config': null,
          },
        ),
      );
    });


    test('check setServerURL', () async {
      _mixpanel.setServerURL("https://api-eu.mixpanel.com");
      expect(
        methodCall,
        isMethodCall(
          'setServerURL',
          arguments: <String, dynamic>{
            'serverURL': 'https://api-eu.mixpanel.com'
          },
        ),
      );
    });

    test('check setLoggingEnabled', () async {
      _mixpanel.setLoggingEnabled(true);
      expect(
        methodCall,
        isMethodCall(
          'setLoggingEnabled',
          arguments: <String, dynamic>{'loggingEnabled': true},
        ),
      );
    });

    test('check setUseIpAddressForGeolocation', () async {
      _mixpanel.setUseIpAddressForGeolocation(true);
      expect(
        methodCall,
        isMethodCall(
          'setUseIpAddressForGeolocation',
          arguments: <String, dynamic>{'useIpAddressForGeolocation': true},
        ),
      );
    });

    test('check optInTracking', () async {
      _mixpanel.optInTracking();
      expect(
        methodCall,
        isMethodCall(
          'optInTracking',
          arguments: null,
        ),
      );
    });

    test('check optOutTracking', () async {
      _mixpanel.optOutTracking();
      expect(
        methodCall,
        isMethodCall(
          'optOutTracking',
          arguments: null,
        ),
      );
    });

    test('check identify', () async {
      _mixpanel.identify("testuser");
      expect(
        methodCall,
        isMethodCall(
          'identify',
          arguments: <String, dynamic>{'distinctId': 'testuser'},
        ),
      );
    });

    test('check alias', () async {
      _mixpanel.alias("alias", "distinctId");
      expect(
        methodCall,
        isMethodCall(
          'alias',
          arguments: <String, dynamic>{
            'alias': 'alias',
            'distinctId': 'distinctId'
          },
        ),
      );
    });

    test('check track call', () async {
      _mixpanel.track("test event");
      expect(
        methodCall,
        isMethodCall(
          'track',
          arguments: <String, dynamic>{
            'eventName': 'test event',
            'properties': null,
          },
        ),
      );
    });

    test('check track with properties call', () async {
      _mixpanel.track("test event", properties: {'a': 'b'});
      expect(
        methodCall,
        isMethodCall(
          'track',
          arguments: <String, dynamic>{
            'eventName': 'test event',
            'properties': <String, dynamic>{'a': 'b'},
          },
        ),
      );
    });

    test('check track with DateTime property', () async {
      final millis = DateTime.now().millisecondsSinceEpoch;
      final date = DateTime.fromMillisecondsSinceEpoch(millis);
      _mixpanel.track("test event", properties: {'date': date});
      expect(
        methodCall,
        isMethodCall(
          'track',
          arguments: <String, dynamic>{
            'eventName': 'test event',
            'properties': <String, dynamic>{'date': date},
          },
        ),
      );
    });

    test('check track with Uri property', () async {
      final url = Uri.parse('https://mixpanel.com');
      _mixpanel.track("test event", properties: {'url': url});
      expect(
        methodCall,
        isMethodCall(
          'track',
          arguments: <String, dynamic>{
            'eventName': 'test event',
            'properties': <String, dynamic>{'url': url},
          },
        ),
      );
    });

    test('check trackWithGroups call', () async {
      _mixpanel.trackWithGroups("tracked with groups", {'a': 1, 'b': 2.3},
          {'company_id': "Mixpanel"});
      expect(
        methodCall,
        isMethodCall(
          'trackWithGroups',
          arguments: <String, dynamic>{
            'eventName': 'tracked with groups',
            'properties': <String, dynamic>{'a': 1, 'b': 2.3},
            'groups': <String, dynamic>{'company_id': "Mixpanel"},
          },
        ),
      );
    });

    test('check setGroup call', () async {
      _mixpanel.setGroup("company_id", 12345);
      expect(
        methodCall,
        isMethodCall(
          'setGroup',
          arguments: <String, dynamic>{
            'groupKey': 'company_id',
            'groupID': 12345,
          },
        ),
      );
    });

    test('check addGroup call', () async {
      _mixpanel.addGroup("company_id", 12345);
      expect(
        methodCall,
        isMethodCall(
          'addGroup',
          arguments: <String, dynamic>{
            'groupKey': 'company_id',
            'groupID': 12345,
          },
        ),
      );
    });

    test('check addGroup call 2', () async {
      _mixpanel.addGroup("company_id", {"test": 123});
      expect(
        methodCall,
        isMethodCall(
          'addGroup',
          arguments: <String, dynamic>{
            'groupKey': 'company_id',
            'groupID': {"test": 123},
          },
        ),
      );
    });

    test('check removeGroup call', () async {
      _mixpanel.removeGroup("company_id", 12345);
      expect(
        methodCall,
        isMethodCall(
          'removeGroup',
          arguments: <String, dynamic>{
            'groupKey': 'company_id',
            'groupID': 12345,
          },
        ),
      );
    });

    test('check deleteGroup call', () async {
      _mixpanel.deleteGroup("company_id", 12345);
      expect(
        methodCall,
        isMethodCall(
          'deleteGroup',
          arguments: <String, dynamic>{
            'groupKey': 'company_id',
            'groupID': 12345,
          },
        ),
      );
    });

    test('check registerSuperProperties call', () async {
      _mixpanel.registerSuperProperties({
        "super property": "super property value",
        "super property1": "super property value1",
      });
      expect(
        methodCall,
        isMethodCall(
          'registerSuperProperties',
          arguments: <String, dynamic>{
            'properties': {
              "super property": "super property value",
              "super property1": "super property value1",
            }
          },
        ),
      );
    });

    test('check registerSuperPropertiesOnce call', () async {
      _mixpanel.registerSuperPropertiesOnce({
        "super property": "super property value",
        "super property1": "super property value1",
      });
      expect(
        methodCall,
        isMethodCall(
          'registerSuperPropertiesOnce',
          arguments: <String, dynamic>{
            'properties': {
              "super property": "super property value",
              "super property1": "super property value1",
            }
          },
        ),
      );
    });

    test('check unregisterSuperProperty call', () async {
      _mixpanel.unregisterSuperProperty("propertyName");
      expect(
        methodCall,
        isMethodCall(
          'unregisterSuperProperty',
          arguments: <String, dynamic>{'propertyName': 'propertyName'},
        ),
      );
    });

    test('check unregisterSuperProperty call', () async {
      _mixpanel.unregisterSuperProperty("propertyName");
      expect(
        methodCall,
        isMethodCall(
          'unregisterSuperProperty',
          arguments: <String, dynamic>{'propertyName': 'propertyName'},
        ),
      );
    });

    test('check getSuperProperties call', () async {
      _mixpanel.getSuperProperties();
      expect(
        methodCall,
        isMethodCall(
          'getSuperProperties',
          arguments: null,
        ),
      );
    });

    test('check clearSuperProperties call', () async {
      _mixpanel.clearSuperProperties();
      expect(
        methodCall,
        isMethodCall(
          'clearSuperProperties',
          arguments: null,
        ),
      );
    });

    test('check timeEvent call', () async {
      _mixpanel.timeEvent("test time event");
      expect(
        methodCall,
        isMethodCall(
          'timeEvent',
          arguments: <String, dynamic>{'eventName': 'test time event'},
        ),
      );
    });

    test('check eventElapsedTime call', () async {
      _mixpanel.eventElapsedTime("test time event");
      expect(
        methodCall,
        isMethodCall(
          'eventElapsedTime',
          arguments: <String, dynamic>{'eventName': 'test time event'},
        ),
      );
    });

    test('check reset call', () async {
      _mixpanel.reset();
      expect(
        methodCall,
        isMethodCall(
          'reset',
          arguments: null,
        ),
      );
    });

    test('check getDistinctId call', () async {
      _mixpanel.getDistinctId();
      expect(
        methodCall,
        isMethodCall(
          'getDistinctId',
          arguments: null,
        ),
      );
    });

    test('check flush call', () async {
      _mixpanel.flush();
      expect(
        methodCall,
        isMethodCall(
          'flush',
          arguments: null,
        ),
      );
    });

    test('check people set call', () async {
      _mixpanel.getPeople().set("prop", 'value');
      expect(
        methodCall,
        isMethodCall(
          'set',
          arguments: <String, dynamic>{
            'token': 'test token',
            'properties': {'prop': 'value'}
          },
        ),
      );
    });

    test('check people setOnce call', () async {
      _mixpanel.getPeople().setOnce("prop", 'value');
      expect(
        methodCall,
        isMethodCall(
          'setOnce',
          arguments: <String, dynamic>{
            'token': 'test token',
            'properties': {'prop': 'value'}
          },
        ),
      );
    });

    test('check increment call', () async {
      _mixpanel.getPeople().increment("a", 1.2);
      expect(
        methodCall,
        isMethodCall(
          'increment',
          arguments: <String, dynamic>{
            'token': 'test token',
            'properties': {'a': 1.2}
          },
        ),
      );
    });

    test('check append call', () async {
      _mixpanel.getPeople().append('a', 1.2);
      expect(
        methodCall,
        isMethodCall(
          'append',
          arguments: <String, dynamic>{
            'token': 'test token',
            'name': 'a',
            'value': 1.2,
          },
        ),
      );
    });

    test('check union call', () async {
      _mixpanel.getPeople().union('a', ['goodbye', 'hi']);
      expect(
        methodCall,
        isMethodCall(
          'union',
          arguments: <String, dynamic>{
            'token': 'test token',
            'name': 'a',
            'value': ['goodbye', 'hi'],
          },
        ),
      );
    });

    test('check remove call', () async {
      _mixpanel.getPeople().remove('c', 5);
      expect(
        methodCall,
        isMethodCall(
          'remove',
          arguments: <String, dynamic>{
            'token': 'test token',
            'name': 'c',
            'value': 5,
          },
        ),
      );
    });

    test('check unset call', () async {
      _mixpanel.getPeople().unset('c');
      expect(
        methodCall,
        isMethodCall(
          'unset',
          arguments: <String, dynamic>{
            'token': 'test token',
            'name': 'c',
          },
        ),
      );
    });

    test('check trackCharge call', () async {
      _mixpanel.getPeople().trackCharge(3);
      expect(
        methodCall,
        isMethodCall(
          'trackCharge',
          arguments: <String, dynamic>{
            'token': 'test token',
            'amount': 3,
            'properties': null,
          },
        ),
      );
    });

    test('check trackCharge call 2', () async {
      _mixpanel.getPeople().trackCharge(3, properties: {'a': 'c'});
      expect(
        methodCall,
        isMethodCall(
          'trackCharge',
          arguments: <String, dynamic>{
            'token': 'test token',
            'amount': 3,
            'properties': {'a': 'c'},
          },
        ),
      );
    });

    test('check clearCharges call', () async {
      _mixpanel.getPeople().clearCharges();
      expect(
        methodCall,
        isMethodCall(
          'clearCharges',
          arguments: <String, dynamic>{
            'token': 'test token',
          },
        ),
      );
    });

    test('check delete user call', () async {
      _mixpanel.getPeople().deleteUser();
      expect(
        methodCall,
        isMethodCall(
          'deleteUser',
          arguments: <String, dynamic>{
            'token': 'test token',
          },
        ),
      );
    });

    test('check group set call', () async {
      _mixpanel.getGroup("company_id", 12345).set("prop_key", "prop_value");
      expect(
        methodCall,
        isMethodCall(
          'groupSetProperties',
          arguments: <String, dynamic>{
            'token': 'test token',
            'groupKey': 'company_id',
            'groupID': 12345,
            'properties': {"prop_key": "prop_value"}
          },
        ),
      );
    });

    test('check group setOnce call', () async {
      _mixpanel.getGroup("company_id", 12345).setOnce("prop_key", "prop_value");
      expect(
        methodCall,
        isMethodCall(
          'groupSetPropertyOnce',
          arguments: <String, dynamic>{
            'token': 'test token',
            'groupKey': 'company_id',
            'groupID': 12345,
            'properties': {"prop_key": "prop_value"}
          },
        ),
      );
    });

    test('check group unset call', () async {
      _mixpanel.getGroup("company_id", 12345).unset("prop_key");
      expect(
        methodCall,
        isMethodCall(
          'groupUnsetProperty',
          arguments: <String, dynamic>{
            'token': 'test token',
            'groupKey': 'company_id',
            'groupID': 12345,
            'propertyName': 'prop_key',
          },
        ),
      );
    });

    test('check group remove call', () async {
      _mixpanel.getGroup("company_id", 12345).remove('prop_key', 'value');
      expect(
        methodCall,
        isMethodCall(
          'groupRemovePropertyValue',
          arguments: <String, dynamic>{
            'token': 'test token',
            'groupKey': 'company_id',
            'groupID': 12345,
            'name': 'prop_key',
            'value': 'value'
          },
        ),
      );
    });

    test('check group union call', () async {
      _mixpanel.getGroup("company_id", 12345).union('prop_key', ['value']);
      expect(
        methodCall,
        isMethodCall(
          'groupUnionProperty',
          arguments: <String, dynamic>{
            'token': 'test token',
            'groupKey': 'company_id',
            'groupID': 12345,
            'name': 'prop_key',
            'value': ['value']
          },
        ),
      );
    });
  });
}
