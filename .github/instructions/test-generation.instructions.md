# Test Generation Instructions for Mixpanel Flutter SDK

## Overview
This document provides specific instructions for generating tests for the Mixpanel Flutter SDK. Follow these patterns to ensure consistency with the existing test suite.

## Test Structure Pattern

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

void main() {
  const MethodChannel channel = MethodChannel('mixpanel_flutter');
  late Mixpanel mixpanel;
  final List<MethodCall> methodCalls = [];

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    mixpanel = Mixpanel('YOUR_MIXPANEL_TOKEN');
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      methodCalls.add(methodCall);
      // Return appropriate mock values based on method
      switch (methodCall.method) {
        case 'getDistinctId':
          return 'distinct_id_1';
        case 'getDeviceId':
          return 'device_id_1';
        case 'getAnonymousId':
          return 'anonymous_id_1';
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  // Test groups go here
}
```

## Core Test Patterns

### 1. Basic Method Call Test
```dart
test('methodName should invoke platform method with correct arguments', () async {
  await mixpanel.methodName('param1', 'param2');
  
  expect(methodCalls, hasLength(1));
  expect(
    methodCalls[0],
    isMethodCall(
      'methodName',
      arguments: <String, dynamic>{
        'param1': 'param1',
        'param2': 'param2',
      },
    ),
  );
});
```

### 2. Validation Test Pattern
```dart
test('methodName should not invoke platform method with invalid input', () async {
  // Test empty string
  await mixpanel.methodName('');
  expect(methodCalls, isEmpty);

  // Test null (if applicable)
  await mixpanel.methodName(null);
  expect(methodCalls, isEmpty);

  // Test whitespace
  await mixpanel.methodName('   ');
  expect(methodCalls, isEmpty);
});
```

### 3. Map/Dictionary Parameter Test
```dart
test('methodName with properties should format correctly', () async {
  final properties = {'key1': 'value1', 'key2': 123, 'key3': true};
  await mixpanel.methodName('param', properties);
  
  expect(
    methodCalls[0],
    isMethodCall(
      'methodName',
      arguments: <String, dynamic>{
        'param': 'param',
        'properties': properties,
      },
    ),
  );
});
```

### 4. Optional Parameter Test
```dart
test('methodName should handle null optional parameters', () async {
  await mixpanel.methodName('required', null);
  
  expect(
    methodCalls[0],
    isMethodCall(
      'methodName',
      arguments: <String, dynamic>{
        'required': 'required',
        'optional': {},  // SDK converts null maps to empty maps
      },
    ),
  );
});
```

## Specific Patterns for SDK Features

### People/Group Accessor Tests
```dart
test('getPeople should return People instance', () {
  final people = mixpanel.getPeople();
  expect(people, isA<People>());
  expect(people, isNotNull);
});

test('getGroup should return MixpanelGroup instance', () {
  final group = mixpanel.getGroup('groupKey', 'groupId');
  expect(group, isA<MixpanelGroup>());
  expect(group, isNotNull);
});
```

### Super Properties Tests
```dart
test('registerSuperProperties should merge properties correctly', () async {
  await mixpanel.registerSuperProperties({'prop1': 'value1'});
  expect(methodCalls, hasLength(1));
  
  await mixpanel.registerSuperProperties({'prop2': 'value2'});
  expect(methodCalls, hasLength(2));
  
  // Both calls should be registerSuperProperties
  expect(methodCalls[0].method, 'registerSuperProperties');
  expect(methodCalls[1].method, 'registerSuperProperties');
});
```

### Time-based Tests
```dart
test('timeEvent should track event timing', () async {
  await mixpanel.timeEvent('Timed Event');
  
  expect(
    methodCalls[0],
    isMethodCall(
      'timeEvent',
      arguments: <String, dynamic>{
        'eventName': 'Timed Event',
      },
    ),
  );
});
```

## Test Coverage Requirements

Each new method should have tests for:

1. **Happy Path**: Valid inputs produce expected platform calls
2. **Validation**: Invalid inputs (empty strings, null where not allowed) are rejected
3. **Edge Cases**: 
   - Very long strings
   - Special characters in strings
   - Empty collections
   - Null optional parameters
4. **Type Safety**: Different property types (String, int, double, bool, List, Map)

## Common Validation Rules

The SDK validates strings using `_MixpanelHelper.isValidString()`:
- Not null
- Not empty after trimming
- Contains at least one non-whitespace character

Test these cases:
```dart
// Invalid strings that should not trigger platform calls
''          // empty
'   '       // whitespace only
'\t\n'      // whitespace characters

// Valid strings that should trigger platform calls
'a'         // single character
'Event'     // normal string
' Event '   // string with surrounding whitespace (gets trimmed)
```

## Platform-Specific Considerations

### Method Return Values
```dart
// For methods that return values
case 'getDistinctId':
  return 'test_distinct_id';
case 'getSuperProperties':
  return {'prop1': 'value1'};
case 'getDeviceId':
  return 'test_device_id';
```

### Complex Type Handling
The SDK uses a custom message codec for DateTime and Uri objects:
```dart
test('track with DateTime property', () async {
  final now = DateTime.now();
  await mixpanel.track('Event', {'timestamp': now});
  
  // DateTime should be passed through the platform channel
  expect(methodCalls[0].arguments['properties']['timestamp'], now);
});
```

## Test Organization

Group related tests:
```dart
group('Event Tracking', () {
  test('track should send event', () async { });
  test('trackWithGroups should include groups', () async { });
  test('timeEvent should start timing', () async { });
});

group('User Profile', () {
  test('identify should set distinct id', () async { });
  test('alias should create alias', () async { });
  test('reset should clear data', () async { });
});

group('Super Properties', () {
  test('registerSuperProperties should register', () async { });
  test('clearSuperProperties should clear all', () async { });
  test('unregisterSuperProperty should remove one', () async { });
});
```

## Example: Complete Test for New Method

```dart
group('newFeature', () {
  test('should invoke platform method with valid inputs', () async {
    await mixpanel.newFeature('param1', {'key': 'value'});
    
    expect(methodCalls, hasLength(1));
    expect(
      methodCalls[0],
      isMethodCall(
        'newFeature',
        arguments: <String, dynamic>{
          'param1': 'param1',
          'properties': {'key': 'value'},
        },
      ),
    );
  });

  test('should not invoke platform method with invalid input', () async {
    await mixpanel.newFeature('', {'key': 'value'});
    expect(methodCalls, isEmpty);
    
    await mixpanel.newFeature('   ', {'key': 'value'});
    expect(methodCalls, isEmpty);
  });

  test('should handle null properties', () async {
    await mixpanel.newFeature('param1', null);
    
    expect(
      methodCalls[0],
      isMethodCall(
        'newFeature',
        arguments: <String, dynamic>{
          'param1': 'param1',
          'properties': {},
        },
      ),
    );
  });

  test('should handle empty properties', () async {
    await mixpanel.newFeature('param1', {});
    
    expect(
      methodCalls[0],
      isMethodCall(
        'newFeature',
        arguments: <String, dynamic>{
          'param1': 'param1',
          'properties': {},
        },
      ),
    );
  });
});
```

## Notes

- Always use `isMethodCall` matcher for asserting method calls
- The SDK converts null maps to empty maps (`{}`) for consistency
- All string parameters are validated before platform calls
- Test both individual methods and their interactions
- Consider platform differences but test through the unified Dart API