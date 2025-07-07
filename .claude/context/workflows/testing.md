# Workflow: Testing

## Test Structure

The SDK uses a multi-layered testing approach:
- **Unit Tests**: Verify platform channel communication
- **Integration Tests**: Manual testing via example app
- **CI Tests**: Automated builds on GitHub Actions

## Running Tests

### Unit Tests
```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/mixpanel_flutter_test.dart
```

### Integration Testing
The example app serves as the integration test suite:
```bash
cd example

# Android
flutter run

# iOS (requires macOS with Xcode)
flutter run

# Web
flutter run -d chrome
```

## Writing Tests

### Platform Channel Tests
All tests mock the platform channel to verify correct method calls:

```dart
test('track sends correct arguments', () async {
  await mixpanel.track('Button Clicked', properties: {
    'button_name': 'purchase',
    'price': 99.99,
  });
  
  expect(
    methodCall,
    isMethodCall(
      'track',
      arguments: <String, dynamic>{
        'eventName': 'Button Clicked',
        'properties': <String, dynamic>{
          'button_name': 'purchase',
          'price': 99.99,
        },
      },
    ),
  );
});
```

### Validation Tests
Test that invalid inputs are handled gracefully:

```dart
test('track ignores empty event name', () async {
  await mixpanel.track('', properties: {'key': 'value'});
  expect(methodCall, null); // No platform call should be made
});

test('identify ignores empty distinct id', () async {
  await mixpanel.identify('');
  expect(methodCall, null);
});
```

### Type Handling Tests
Test custom codec functionality:

```dart
test('handles DateTime in properties', () async {
  final now = DateTime.now();
  await mixpanel.track('Test', properties: {'timestamp': now});
  
  expect(
    methodCall,
    isMethodCall(
      'track',
      arguments: <String, dynamic>{
        'eventName': 'Test',
        'properties': <String, dynamic>{'timestamp': now},
      },
    ),
  );
});
```

## Test Patterns

### Setup and Teardown
```dart
late MethodChannel methodChannel;
MethodCall? methodCall;
late Mixpanel mixpanel;

setUp(() async {
  methodChannel = const MethodChannel('mixpanel_flutter');
  
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
    methodCall = call;
    return null;
  });
  
  mixpanel = await Mixpanel.init("test_token", trackAutomaticEvents: false);
});

tearDown(() {
  methodCall = null;
});
```

### Custom Matchers
The SDK includes custom matchers for method calls:

```dart
Matcher isMethodCall(String method, {dynamic arguments}) {
  return _IsMethodCall(method, arguments);
}

class _IsMethodCall extends Matcher {
  final String method;
  final dynamic arguments;

  const _IsMethodCall(this.method, this.arguments);

  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) {
    if (item is! MethodCall) return false;
    if (item.method != method) return false;
    return arguments == null || item.arguments == arguments;
  }
}
```

## Platform-Specific Testing

### Android Testing
```bash
cd example
flutter build apk
# Install on device/emulator
flutter install
```

### iOS Testing
```bash
cd example
flutter build ios --simulator
# Run on simulator
flutter run
```

### Web Testing
```bash
cd example
flutter build web
# Serve locally
python -m http.server 8080 --directory build/web
```

## CI Testing

GitHub Actions runs tests automatically on push/PR:

### Test Matrix
- **Flutter Version**: Latest stable
- **Platforms**: Ubuntu (Android), macOS (iOS)
- **Jobs**:
  1. Unit tests and static analysis
  2. Android APK build
  3. iOS simulator build

### CI Commands
```yaml
# Unit tests
flutter test --no-pub

# Static analysis
flutter analyze --no-pub --no-current-package lib

# Android build
cd example && flutter build apk

# iOS build
cd example && flutter build ios --debug --simulator --no-codesign
```

## Testing Checklist

Before submitting PR:
- [ ] All unit tests pass
- [ ] Static analysis has no errors
- [ ] Example app runs on Android
- [ ] Example app runs on iOS
- [ ] Example app runs on Web
- [ ] New features have corresponding tests
- [ ] Edge cases are tested (empty strings, null values)
- [ ] CI builds are green

## Common Test Issues

### Platform Channel Not Mocked
```dart
// Incorrect - will fail
final mixpanel = Mixpanel('token');

// Correct - use init method
final mixpanel = await Mixpanel.init('token', trackAutomaticEvents: false);
```

### Async Test Issues
```dart
// Always use async/await in tests
test('async test', () async {
  await mixpanel.track('event');
  // assertions...
});
```

### Type Comparison
```dart
// Be careful with type checking
expect(methodCall.arguments['properties'], isA<Map<String, dynamic>>());
```