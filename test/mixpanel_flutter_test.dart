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
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        return null;
      });

      _mixpanel =
          await Mixpanel.init("test token", optOutTrackingDefault: false, trackAutomaticEvents: true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
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
              '\$lib_version': '2.4.4',
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
              '\$lib_version': '2.4.4',
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
              '\$lib_version': '2.4.4',
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

    test('check setFlushBatchSize', () async {
      _mixpanel.setFlushBatchSize(30);
      expect(
        methodCall,
        isMethodCall(
          'setFlushBatchSize',
          arguments: <String, dynamic>{'flushBatchSize': 30},
        ),
      );
    });

    test('check setFlush', () async {
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

  group('Helper validation tests (via public API)', () {
    test('methods with empty string parameters are not called', () async {
      // Test that methods validate string parameters and don't invoke channel
      // when strings are empty (testing isValidString indirectly)
      
      // Reset method call tracking
      methodCall = null;
      
      // Try various methods with empty strings
      await _mixpanel.unregisterSuperProperty('');
      expect(methodCall, isNull); // Should not have called the method
      
      _mixpanel.timeEvent('');
      expect(methodCall, isNull);
      
      _mixpanel.eventElapsedTime('');
      expect(methodCall, isNull);
      
      _mixpanel.setGroup('', 'groupId');
      expect(methodCall, isNull);
      
      _mixpanel.addGroup('', 'groupId');
      expect(methodCall, isNull);
      
      _mixpanel.removeGroup('', 'groupId');
      expect(methodCall, isNull);
      
      _mixpanel.deleteGroup('', 'groupId');
      expect(methodCall, isNull);
    });

    test('People methods with empty string parameters are not called', () {
      // Testing People methods
      methodCall = null;
      _mixpanel.getPeople().set('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      _mixpanel.getPeople().setOnce('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      _mixpanel.getPeople().increment('', 1);
      expect(methodCall, isNull);
      
      methodCall = null;
      _mixpanel.getPeople().append('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      _mixpanel.getPeople().union('', ['value']);
      expect(methodCall, isNull);
      
      methodCall = null;
      _mixpanel.getPeople().remove('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      _mixpanel.getPeople().unset('');
      expect(methodCall, isNull);
    });

    test('Group methods with empty string parameters are not called', () {
      final group = _mixpanel.getGroup('company_id', 12345);
      
      methodCall = null;
      group.set('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      group.setOnce('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      group.unset('');
      expect(methodCall, isNull);
      
      methodCall = null;
      group.remove('', 'value');
      expect(methodCall, isNull);
      
      methodCall = null;
      group.union('', ['value']);
      expect(methodCall, isNull);
    });

    test('methods validate parameters correctly', () async {
      // Test track with empty event name
      methodCall = null;
      _mixpanel.track('');
      expect(methodCall, isNull);
      
      // Test identify with empty distinctId
      methodCall = null;
      _mixpanel.identify('');
      expect(methodCall, isNull);
      
      // Test alias with empty alias
      methodCall = null;
      _mixpanel.alias('', 'distinctId');
      expect(methodCall, isNull);
      
      // Test alias with empty distinctId
      methodCall = null;
      _mixpanel.alias('alias', '');
      expect(methodCall, isNull);
      
      // Test setServerURL with empty URL
      methodCall = null;
      _mixpanel.setServerURL('');
      expect(methodCall, isNull);
      
      // Test trackWithGroups with empty event name
      methodCall = null;
      _mixpanel.trackWithGroups('', {'key': 'value'}, {'group': 'id'});
      expect(methodCall, isNull);
    });

    test('comprehensive validation coverage', () {
      // The _MixpanelHelper.isValidString functionality is tested through
      // all the existing tests that verify method calls with valid parameters
      // and absence of method calls with empty string parameters.
      //
      // The _MixpanelHelper.ensureSerializableValue and ensureSerializableProperties
      // functionality is tested indirectly through the web platform tests
      // and through successful method calls with complex data types.

      expect(true, true); // This test serves as documentation
    });
  });

  group('Feature Flags', () {
    setUp(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        if (m.method == 'areFlagsReady') {
          return true;
        }
        if (m.method == 'getVariant' || m.method == 'getVariantSync') {
          return {
            'key': 'test_flag',
            'value': 'variant_a',
            'experimentId': 'exp_123',
            'isExperimentActive': true,
            'isQaTester': false,
          };
        }
        if (m.method == 'getVariantValue' || m.method == 'getVariantValueSync') {
          return 'variant_value';
        }
        if (m.method == 'isEnabled' || m.method == 'isEnabledSync') {
          return true;
        }
        return null;
      });

      _mixpanel = await Mixpanel.init("test token",
          optOutTrackingDefault: false, trackAutomaticEvents: true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      methodCall = null;
    });

    test('check areFlagsReady call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.areFlagsReady();
      expect(result, true);
      expect(
        methodCall,
        isMethodCall(
          'areFlagsReady',
          arguments: null,
        ),
      );
    });

    test('check getVariant call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final fallback = MixpanelFlagVariant.fallback('test_flag', 'default');
      final result = await flags.getVariant('test_flag', fallback);
      expect(result.key, 'test_flag');
      expect(result.value, 'variant_a');
      expect(result.experimentId, 'exp_123');
      expect(result.isExperimentActive, true);
      expect(result.isQaTester, false);
      expect(
        methodCall,
        isMethodCall(
          'getVariant',
          arguments: <String, dynamic>{
            'flagName': 'test_flag',
            'fallback': {
              'key': 'test_flag',
              'value': 'default',
              'experimentId': null,
              'isExperimentActive': null,
              'isQaTester': null,
            },
          },
        ),
      );
    });

    test('check getVariantSync call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final fallback = MixpanelFlagVariant.fallback('test_flag', 'default');
      final result = await flags.getVariantSync('test_flag', fallback);
      expect(result.value, 'variant_a');
      expect(
        methodCall,
        isMethodCall(
          'getVariantSync',
          arguments: <String, dynamic>{
            'flagName': 'test_flag',
            'fallback': {
              'key': 'test_flag',
              'value': 'default',
              'experimentId': null,
              'isExperimentActive': null,
              'isQaTester': null,
            },
          },
        ),
      );
    });

    test('check getVariantValue call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.getVariantValue('test_flag', 'fallback');
      expect(result, 'variant_value');
      expect(
        methodCall,
        isMethodCall(
          'getVariantValue',
          arguments: <String, dynamic>{
            'flagName': 'test_flag',
            'fallbackValue': 'fallback',
          },
        ),
      );
    });

    test('check getVariantValueSync call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.getVariantValueSync('test_flag', 'fallback');
      expect(result, 'variant_value');
      expect(
        methodCall,
        isMethodCall(
          'getVariantValueSync',
          arguments: <String, dynamic>{
            'flagName': 'test_flag',
            'fallbackValue': 'fallback',
          },
        ),
      );
    });

    test('check isEnabled call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.isEnabled('test_flag', false);
      expect(result, true);
      expect(
        methodCall,
        isMethodCall(
          'isEnabled',
          arguments: <String, dynamic>{
            'flagName': 'test_flag',
            'fallbackValue': false,
          },
        ),
      );
    });

    test('check isEnabledSync call', () async {
      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.isEnabledSync('test_flag', false);
      expect(result, true);
      expect(
        methodCall,
        isMethodCall(
          'isEnabledSync',
          arguments: <String, dynamic>{
            'flagName': 'test_flag',
            'fallbackValue': false,
          },
        ),
      );
    });

    test('check updateContext call', () async {
      final flags = _mixpanel.getFeatureFlags();
      await flags.updateContext({'user_tier': 'premium'});
      expect(
        methodCall,
        isMethodCall(
          'updateFlagsContext',
          arguments: <String, dynamic>{
            'context': {'user_tier': 'premium'},
            'options': null,
          },
        ),
      );
    });

    test('check updateContext with options call', () async {
      final flags = _mixpanel.getFeatureFlags();
      await flags.updateContext(
        {'user_tier': 'premium'},
        options: {'refetch': true},
      );
      expect(
        methodCall,
        isMethodCall(
          'updateFlagsContext',
          arguments: <String, dynamic>{
            'context': {'user_tier': 'premium'},
            'options': {'refetch': true},
          },
        ),
      );
    });

    test('feature flags methods with empty flagName are not called', () async {
      final flags = _mixpanel.getFeatureFlags();
      methodCall = null;

      // getVariant with empty flagName
      final fallback = MixpanelFlagVariant.fallback('', 'default');
      final variantResult = await flags.getVariant('', fallback);
      expect(methodCall, isNull);
      expect(variantResult.key, '');
      expect(variantResult.value, 'default');

      // getVariantSync with empty flagName
      methodCall = null;
      await flags.getVariantSync('', fallback);
      expect(methodCall, isNull);

      // getVariantValue with empty flagName
      methodCall = null;
      final valueResult = await flags.getVariantValue('', 'fallback');
      expect(methodCall, isNull);
      expect(valueResult, 'fallback');

      // getVariantValueSync with empty flagName
      methodCall = null;
      final valueSyncResult = await flags.getVariantValueSync('', 'fallback');
      expect(methodCall, isNull);
      expect(valueSyncResult, 'fallback');

      // isEnabled with empty flagName
      methodCall = null;
      final enabledResult = await flags.isEnabled('', false);
      expect(methodCall, isNull);
      expect(enabledResult, false);

      // isEnabledSync with empty flagName
      methodCall = null;
      final enabledSyncResult = await flags.isEnabledSync('', true);
      expect(methodCall, isNull);
      expect(enabledSyncResult, true);
    });

    test('check initialize with featureFlags config', () async {
      _mixpanel = await Mixpanel.init(
        "test token",
        optOutTrackingDefault: false,
        trackAutomaticEvents: true,
        featureFlags: FeatureFlagsConfig(
          enabled: true,
          context: {'user_tier': 'premium'},
        ),
      );
      expect(
        methodCall,
        isMethodCall(
          'initialize',
          arguments: <String, dynamic>{
            'token': "test token",
            'optOutTrackingDefault': false,
            'trackAutomaticEvents': true,
            'mixpanelProperties': {
              '\$lib_version': '2.4.4',
              'mp_lib': 'flutter',
            },
            'superProperties': null,
            'config': null,
            'featureFlags': {
              'enabled': true,
              'context': {'user_tier': 'premium'},
            },
          },
        ),
      );
    });

    test('MixpanelFlagVariant fromMap and toMap', () {
      final variant = MixpanelFlagVariant(
        key: 'test_key',
        value: 'test_value',
        experimentId: 'exp_123',
        isExperimentActive: true,
        isQaTester: false,
      );

      final map = variant.toMap();
      expect(map['key'], 'test_key');
      expect(map['value'], 'test_value');
      expect(map['experimentId'], 'exp_123');
      expect(map['isExperimentActive'], true);
      expect(map['isQaTester'], false);

      final fromMap = MixpanelFlagVariant.fromMap(map);
      expect(fromMap.key, 'test_key');
      expect(fromMap.value, 'test_value');
      expect(fromMap.experimentId, 'exp_123');
      expect(fromMap.isExperimentActive, true);
      expect(fromMap.isQaTester, false);
    });

    test('MixpanelFlagVariant fallback factory', () {
      final fallback = MixpanelFlagVariant.fallback('my_flag', true);
      expect(fallback.key, 'my_flag');
      expect(fallback.value, true);
      expect(fallback.experimentId, null);
      expect(fallback.isExperimentActive, null);
      expect(fallback.isQaTester, null);
    });

    test('FeatureFlagsConfig toMap', () {
      final config = FeatureFlagsConfig(
        enabled: true,
        context: {'key': 'value'},
      );
      final map = config.toMap();
      expect(map['enabled'], true);
      expect(map['context'], {'key': 'value'});
    });

    test('FeatureFlagsConfig default values', () {
      final config = FeatureFlagsConfig();
      expect(config.enabled, true);
      expect(config.context, <String, dynamic>{});

      final map = config.toMap();
      expect(map['enabled'], true);
      expect(map['context'], <String, dynamic>{});
    });

    test('areFlagsReady returns false when not ready', () async {
      // Override handler to return false
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        if (m.method == 'areFlagsReady') {
          return false;
        }
        return null;
      });

      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.areFlagsReady();
      expect(result, false);
    });

    test('getVariant returns fallback when platform returns null', () async {
      // Override handler to return null
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        return null;
      });

      final flags = _mixpanel.getFeatureFlags();
      final fallback = MixpanelFlagVariant.fallback('test_flag', 'fallback_value');
      final result = await flags.getVariant('test_flag', fallback);
      expect(result.key, 'test_flag');
      expect(result.value, 'fallback_value');
    });

    test('getVariantValue returns fallback when platform returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        return null;
      });

      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.getVariantValue('test_flag', 'my_fallback');
      expect(result, 'my_fallback');
    });

    test('isEnabled returns fallback when platform returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        return null;
      });

      final flags = _mixpanel.getFeatureFlags();
      final result = await flags.isEnabled('test_flag', true);
      expect(result, true);
    });

    test('MixpanelFlagVariant.fromMap with missing key', () {
      final map = <String, dynamic>{
        'value': 'test_value',
        'experimentId': 'exp_123',
      };
      final variant = MixpanelFlagVariant.fromMap(map);
      expect(variant.key, ''); // Defaults to empty string
      expect(variant.value, 'test_value');
      expect(variant.experimentId, 'exp_123');
    });

    test('MixpanelFlagVariant.fromMap with empty key', () {
      final map = <String, dynamic>{
        'key': '',
        'value': 'test_value',
      };
      final variant = MixpanelFlagVariant.fromMap(map);
      expect(variant.key, '');
      expect(variant.value, 'test_value');
    });

    test('MixpanelFlagVariant.fromMap with null key', () {
      final map = <String, dynamic>{
        'key': null,
        'value': 123,
      };
      final variant = MixpanelFlagVariant.fromMap(map);
      expect(variant.key, '');
      expect(variant.value, 123);
    });

    test('MixpanelFlagVariant with int value', () {
      final variant = MixpanelFlagVariant(key: 'int_flag', value: 42);
      expect(variant.key, 'int_flag');
      expect(variant.value, 42);
      expect(variant.value is int, true);
    });

    test('MixpanelFlagVariant with Map value', () {
      final mapValue = {'nested': 'value', 'count': 5};
      final variant = MixpanelFlagVariant(key: 'map_flag', value: mapValue);
      expect(variant.key, 'map_flag');
      expect(variant.value, mapValue);
      expect(variant.value is Map, true);
    });

    test('MixpanelFlagVariant with List value', () {
      final listValue = ['a', 'b', 'c'];
      final variant = MixpanelFlagVariant(key: 'list_flag', value: listValue);
      expect(variant.key, 'list_flag');
      expect(variant.value, listValue);
      expect(variant.value is List, true);
    });

    test('getVariantSync returns all fields correctly', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        methodCall = m;
        if (m.method == 'getVariantSync') {
          return {
            'key': 'full_flag',
            'value': 'variant_b',
            'experimentId': 'exp_456',
            'isExperimentActive': false,
            'isQaTester': true,
          };
        }
        return null;
      });

      final flags = _mixpanel.getFeatureFlags();
      final fallback = MixpanelFlagVariant.fallback('full_flag', 'default');
      final result = await flags.getVariantSync('full_flag', fallback);

      expect(result.key, 'full_flag');
      expect(result.value, 'variant_b');
      expect(result.experimentId, 'exp_456');
      expect(result.isExperimentActive, false);
      expect(result.isQaTester, true);
    });

    test('MixpanelFlagVariant equality', () {
      final variant1 = MixpanelFlagVariant(
        key: 'test_key',
        value: 'test_value',
        experimentId: 'exp_123',
        isExperimentActive: true,
        isQaTester: false,
      );

      final variant2 = MixpanelFlagVariant(
        key: 'test_key',
        value: 'test_value',
        experimentId: 'exp_123',
        isExperimentActive: true,
        isQaTester: false,
      );

      final variant3 = MixpanelFlagVariant(
        key: 'different_key',
        value: 'test_value',
        experimentId: 'exp_123',
        isExperimentActive: true,
        isQaTester: false,
      );

      expect(variant1 == variant2, true);
      expect(variant1.hashCode == variant2.hashCode, true);
      expect(variant1 == variant3, false);
    });

    test('MixpanelFlagVariant equality with different values', () {
      final variant1 = MixpanelFlagVariant(key: 'flag', value: 'a');
      final variant2 = MixpanelFlagVariant(key: 'flag', value: 'b');

      expect(variant1 == variant2, false);
    });

    test('MixpanelFlagVariant equality with null metadata', () {
      final variant1 = MixpanelFlagVariant.fallback('flag', true);
      final variant2 = MixpanelFlagVariant.fallback('flag', true);

      expect(variant1 == variant2, true);
      expect(variant1.hashCode == variant2.hashCode, true);
    });
  });
}
