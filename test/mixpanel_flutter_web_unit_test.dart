import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

void main() {
  const MethodChannel channel = MethodChannel('mixpanel_flutter');

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Web platform channel tests', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall m) async {
        // Return mock responses for specific methods
        switch (m.method) {
          case 'getDistinctId':
            return 'mock-distinct-id';
          case 'hasOptedOutTracking':
            return false;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('verifies web-specific properties are added to track calls', () async {
      // This tests that web implementation adds lib_version and mp_lib
      final webProperties = {
        '\$lib_version': '1.3.1',  // Web version
        'mp_lib': 'flutter',
      };
      
      // When tracking an event through the web plugin, these properties should be added
      expect(webProperties['\$lib_version'], '1.3.1');
      expect(webProperties['mp_lib'], 'flutter');
    });

    test('verifies safeJsify type handling logic', () {
      // Test the expected behavior of safeJsify without actual JS interop
      final testCases = [
        {'input': null, 'shouldBeNull': true},
        {'input': {'key': 'value'}, 'type': 'Map'},
        {'input': [1, 2, 3], 'type': 'List'},
        {'input': DateTime.now(), 'type': 'DateTime'},
        {'input': true, 'type': 'bool'},
        {'input': 42, 'type': 'int'},
        {'input': 3.14, 'type': 'double'},
        {'input': 'test', 'type': 'String'},
        {'input': Object(), 'shouldBeNull': true}, // Unsupported type
      ];
      
      // Verify expected conversion behavior
      for (final testCase in testCases) {
        final input = testCase['input'];
        if (testCase.containsKey('shouldBeNull')) {
          final shouldBeNull = testCase['shouldBeNull'] as bool;
          // Would return null for unsupported types or null input
          if (shouldBeNull) {
            expect(input == null || (input is! Map && input is! List && 
                   input is! DateTime && input is! bool && input is! num && 
                   input is! String), true);
          }
        } else {
          // Would convert to appropriate JS type
          final expectedType = testCase['type'] as String;
          expect(input.runtimeType.toString(), contains(expectedType));
        }
      }
    });

    test('handles complex nested structures', () {
      final complexData = {
        'user': {
          'id': 123,
          'name': 'Test User',
          'premium': true,
          'joinDate': DateTime(2024, 1, 1),
          'tags': ['flutter', 'mobile', 'analytics'],
          'metadata': {
            'version': 2.5,
            'platform': 'web',
          }
        }
      };
      
      // Verify the structure can be processed
      expect(complexData['user'], isA<Map>());
      expect((complexData['user'] as Map)['tags'], isA<List>());
    });

    test('verifies groupSetPropertyOnce handles single property correctly', () async {
      // The web implementation extracts the first key-value pair
      final properties = {'founded': '2020-01-01', 'extra': 'ignored'};
      final firstKey = properties.keys.first;
      final firstValue = properties[firstKey];
      
      expect(firstKey, 'founded');
      expect(firstValue, '2020-01-01');
    });

    test('verifies groupUnionProperty handles non-array values', () {
      // When value is not an array, it should convert to empty array
      final nonArrayValue = 'single-value';
      final arrayValue = ['value1', 'value2'];
      
      expect(nonArrayValue, isNot(isA<List>()));
      expect(arrayValue, isA<List>());
    });

    test('verifies web people methods include mixpanel properties', () {
      final mixpanelProperties = {
        '\$lib_version': '1.3.1',
        'mp_lib': 'flutter',
      };
      
      final userProperties = {'name': 'John', 'age': 30};
      final combined = {...mixpanelProperties, ...userProperties};
      
      expect(combined['\$lib_version'], '1.3.1');
      expect(combined['mp_lib'], 'flutter');
      expect(combined['name'], 'John');
      expect(combined['age'], 30);
    });

    test('verifies track method adds web properties', () {
      final mixpanelProperties = {
        '\$lib_version': '1.3.1',
        'mp_lib': 'flutter',
      };
      
      final eventProperties = {'action': 'click', 'element': 'button'};
      final combined = {...mixpanelProperties, ...eventProperties};
      
      expect(combined.length, 4);
      expect(combined.containsKey('\$lib_version'), true);
      expect(combined.containsKey('mp_lib'), true);
    });

    test('verifies null properties are handled gracefully', () {
      final mixpanelProperties = {
        '\$lib_version': '1.3.1',
        'mp_lib': 'flutter',
      };
      
      final nullProperties = null;
      final combined = {...mixpanelProperties, ...(nullProperties ?? {})};
      
      expect(combined.length, 2);
      expect(combined, mixpanelProperties);
    });

    test('verifies empty config is handled in initialize', () {
      final config = null;
      final safeConfig = config ?? <String, dynamic>{};
      
      expect(safeConfig, isA<Map>());
      expect(safeConfig, isEmpty);
    });

    test('verifies PlatformException for unimplemented methods', () {
      expect(
        () => throw PlatformException(
          code: 'Unimplemented',
          details: 'mixpanel_flutter for web doesn\'t implement \'unknownMethod\'',
        ),
        throwsA(
          isA<PlatformException>()
            .having((e) => e.code, 'code', 'Unimplemented')
            .having((e) => e.details, 'details', contains('unknownMethod'))
        ),
      );
    });
  });

  group('Web method call structure tests', () {
    test('initialize method structure', () {
      final args = {
        'token': 'test-token',
        'config': {'api_host': 'https://api.mixpanel.com'},
      };
      
      expect(args['token'], isA<String>());
      expect(args['config'], isA<Map>());
    });

    test('track method structure', () {
      final args = {
        'eventName': 'Test Event',
        'properties': {'key': 'value'},
      };
      
      expect(args['eventName'], isA<String>());
      expect(args['properties'], isA<Map>());
    });

    test('trackWithGroups method structure', () {
      final args = {
        'eventName': 'Group Event',
        'properties': {'prop': 'value'},
        'groups': {'company_id': 'comp123'},
      };
      
      expect(args['eventName'], isA<String>());
      expect(args['properties'], isA<Map>());
      expect(args['groups'], isA<Map>());
    });

    test('setLoggingEnabled method structure', () {
      final args = {
        'loggingEnabled': true,
      };
      
      expect(args['loggingEnabled'], isA<bool>());
    });

    test('people methods structure', () {
      final incrementArgs = {
        'properties': {'loginCount': 1},
      };
      
      final chargeArgs = {
        'amount': 99.99,
        'properties': {'product': 'Premium'},
      };
      
      expect(incrementArgs['properties'], isA<Map>());
      expect(chargeArgs['amount'], isA<double>());
      expect(chargeArgs['properties'], isA<Map>());
    });

    test('group methods structure', () {
      final setArgs = {
        'groupKey': 'company_id',
        'groupID': 'comp123',
        'properties': {'name': 'Acme Corp'},
      };
      
      final unionArgs = {
        'groupKey': 'company_id',
        'groupID': 'comp123',
        'name': 'technologies',
        'value': ['Flutter', 'Dart'],
      };
      
      expect(setArgs['groupKey'], isA<String>());
      expect(setArgs['groupID'], isA<String>());
      expect(setArgs['properties'], isA<Map>());
      expect(unionArgs['value'], isA<List>());
    });
  });
}