# AGENTS.md - Test Generation Guide

This file provides specialized guidance for AI agents generating tests for the Mixpanel Flutter SDK example app.

## Test Architecture Overview

### Test Types
1. **Widget Tests** - UI component testing with mocked platform channels
2. **Integration Tests** - Full app flow testing with real platform interactions
3. **Unit Tests** - Individual method and class testing

### Platform Channel Mocking Strategy

```dart
// Standard mock setup for all tests
void setupMixpanelMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  const MethodChannel channel = MethodChannel('mixpanel_flutter');
  final List<MethodCall> log = <MethodCall>[];
  
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    log.add(methodCall);
    
    // Return appropriate mock responses
    switch (methodCall.method) {
      case 'getDistinctId':
        return 'test_distinct_id';
      case 'getDeviceId':
        return 'test_device_id';
      case 'track':
      case 'trackWithGroups':
      case 'timeEvent':
      case 'eventElapsedTime':
      case 'identify':
      case 'alias':
      case 'registerSuperProperties':
      case 'registerSuperPropertiesOnce':
      case 'unregisterSuperProperty':
      case 'reset':
      case 'clearSuperProperties':
      case 'flush':
        return null; // void methods
      case 'getSuperProperties':
        return <String, dynamic>{};
      case 'optInTracking':
      case 'optOutTracking':
      case 'hasOptedOutTracking':
        return methodCall.arguments['hasOptedOutTracking'] ?? false;
      default:
        return null;
    }
  });
}
```

## Analytics SDK Test Patterns

### Event Tracking Tests
```dart
testWidgets('tracks events with properties', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  
  // Find and tap button
  await tester.tap(find.text('Track Event'));
  await tester.pump();
  
  // Verify platform channel call
  expect(log.last.method, 'track');
  expect(log.last.arguments['eventName'], 'Button Clicked');
  expect(log.last.arguments['properties'], isA<Map<String, dynamic>>());
});
```

### User Profile Tests
```dart
testWidgets('updates user profile properties', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  
  // Navigate to profile page
  await tester.tap(find.text('User Profile'));
  await tester.pumpAndSettle();
  
  // Set profile property
  await tester.enterText(find.byType(TextField).first, 'Test User');
  await tester.tap(find.text('Set Name'));
  await tester.pump();
  
  // Verify people.set call
  expect(log.last.method, 'people.set');
  expect(log.last.arguments['properties']['name'], 'Test User');
});
```

### Group Analytics Tests
```dart
testWidgets('manages group analytics', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  
  // Navigate to groups
  await tester.tap(find.text('Groups'));
  await tester.pumpAndSettle();
  
  // Add user to group
  await tester.tap(find.text('Add to Group'));
  await tester.pump();
  
  expect(log.last.method, 'group.set');
  expect(log.last.arguments['groupKey'], 'company');
});
```

## Coverage Goals

### Minimum Coverage Requirements
- **Overall**: 80% line coverage
- **Critical paths**: 95% coverage
  - Event tracking
  - User identification
  - Super properties
  - Data persistence

### Coverage Exclusions
- Generated code (`*.g.dart`)
- Platform-specific implementations
- Example app UI code (focus on SDK usage)

## Common Test Scenarios

### 1. Event Tracking Scenarios
- [ ] Basic event tracking
- [ ] Events with properties
- [ ] Events with groups
- [ ] Timed events
- [ ] Super properties inheritance
- [ ] Property validation

### 2. User Management Scenarios
- [ ] User identification
- [ ] Alias creation
- [ ] Profile property updates
- [ ] Incremental operations
- [ ] List operations (append, union)
- [ ] User deletion

### 3. Data Persistence Scenarios
- [ ] Super properties persistence
- [ ] Distinct ID persistence
- [ ] Opt-out state persistence
- [ ] Flush behavior

### 4. Error Handling Scenarios
- [ ] Invalid event names
- [ ] Null properties
- [ ] Network failures
- [ ] Platform errors

### 5. Web-Specific Scenarios
- [ ] Script loading
- [ ] JavaScript interop
- [ ] Type conversion

## Integration Test Guidelines

### Setup Pattern
```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('Mixpanel Integration', () {
    setUpAll(() async {
      // Initialize real Mixpanel instance
      await Mixpanel.init('YOUR_TOKEN');
    });
    
    testWidgets('full user journey', (WidgetTester tester) async {
      await tester.pumpWidget(MyApp());
      
      // Test complete user flow
      // 1. Track app open
      // 2. Identify user
      // 3. Track feature usage
      // 4. Update profile
      // 5. Join group
      // 6. Track conversion
    });
  });
}
```

### Platform-Specific Integration Tests
```dart
// Run only on specific platforms
testWidgets('iOS specific features', (WidgetTester tester) async {
  if (!Platform.isIOS) return;
  
  // Test iOS-specific functionality
}, skip: !Platform.isIOS);
```

## Test Data Generators

### Property Generators
```dart
Map<String, dynamic> generateTestProperties({
  bool includeNested = false,
  bool includeArrays = false,
  bool includeDates = false,
}) {
  final props = <String, dynamic>{
    'string_prop': 'test_value',
    'int_prop': 42,
    'double_prop': 3.14,
    'bool_prop': true,
  };
  
  if (includeNested) {
    props['nested'] = {'level': 2, 'data': 'nested_value'};
  }
  
  if (includeArrays) {
    props['array'] = ['item1', 'item2', 'item3'];
  }
  
  if (includeDates) {
    props['date'] = DateTime.now();
  }
  
  return props;
}
```

### Event Name Generators
```dart
const List<String> testEventNames = [
  'App Opened',
  'Feature Used',
  'Button Clicked',
  'Form Submitted',
  'Purchase Completed',
  'Error Occurred',
];

String generateEventName() => 
    testEventNames[Random().nextInt(testEventNames.length)];
```

## Performance Test Patterns

### Batch Operations
```dart
test('handles high volume events', () async {
  final stopwatch = Stopwatch()..start();
  
  // Track 1000 events
  for (int i = 0; i < 1000; i++) {
    await mixpanel.track('Test Event $i');
  }
  
  stopwatch.stop();
  expect(stopwatch.elapsedMilliseconds, lessThan(5000));
});
```

### Memory Usage
```dart
test('maintains reasonable memory footprint', () async {
  // Monitor memory before
  final initialMemory = await getMemoryUsage();
  
  // Perform operations
  for (int i = 0; i < 100; i++) {
    await mixpanel.registerSuperProperties({
      'prop_$i': 'value_$i'
    });
  }
  
  // Check memory growth
  final finalMemory = await getMemoryUsage();
  expect(finalMemory - initialMemory, lessThan(10 * 1024 * 1024)); // 10MB
});
```

## Mock Helpers

### Platform Response Mocks
```dart
class MockMixpanelResponses {
  static final Map<String, dynamic> superProperties = {
    'app_version': '1.0.0',
    'platform': 'flutter',
  };
  
  static const String distinctId = 'mock_distinct_id_123';
  static const String deviceId = 'mock_device_id_456';
  
  static Map<String, dynamic> peopleProperties = {
    '\$name': 'Test User',
    '\$email': 'test@example.com',
    'created': DateTime.now().toIso8601String(),
  };
}
```

### Test Matchers
```dart
Matcher isTrackCall(String eventName, [Map<String, dynamic>? properties]) {
  return allOf(
    isMethodCall('track', arguments: {
      'eventName': eventName,
      if (properties != null) 'properties': properties,
    }),
  );
}

Matcher isPeopleCall(String operation, Map<String, dynamic> properties) {
  return isMethodCall('people.$operation', arguments: {
    'properties': properties,
  });
}
```

## CI/CD Test Commands

```bash
# Run all tests with coverage
flutter test --coverage

# Generate coverage report
genhtml coverage/lcov.info -o coverage/html

# Run specific test file
flutter test test/widget_test.dart

# Run integration tests
flutter test integration_test/app_test.dart

# Run tests on specific platform
flutter test --platform chrome  # Web
flutter test --device-id <id>   # Specific device
```

## Test Debugging Tips

### Verbose Platform Channel Logging
```dart
// Add to setUp()
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
  print('Platform call: ${methodCall.method}');
  print('Arguments: ${methodCall.arguments}');
  // ... handle call
});
```

### Visual Test Debugging
```dart
// Take screenshots during failed tests
testWidgets('visual debugging', (WidgetTester tester) async {
  await tester.pumpWidget(MyApp());
  
  try {
    // Test logic
  } catch (e) {
    // Take screenshot on failure
    await tester.takeScreenshot(name: 'failure_screenshot');
    rethrow;
  }
});
```

## Quick Test Templates

### Basic Widget Test
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  setUpAll(() => setupMixpanelMocks());
  
  testWidgets('description', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    
    // Test implementation
  });
}
```

### Property Validation Test
```dart
test('validates properties', () async {
  // Test null handling
  await mixpanel.track('Event', null);
  expect(log.last.arguments['properties'], {});
  
  // Test invalid types
  await mixpanel.track('Event', {'invalid': Object()});
  // Should filter out invalid types
});
```

This guide ensures comprehensive, consistent test coverage across the Mixpanel Flutter SDK example app.