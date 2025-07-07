# Add New Analytics Method to Mixpanel Flutter SDK

Use this prompt when you need to add a new analytics method to the Mixpanel Flutter SDK.

## Context
You are adding a new method to the Mixpanel Flutter SDK. This SDK wraps native Mixpanel SDKs for iOS, Android, and Web platforms, providing a unified Dart API.

## Method Details
- **Method Name**: `[METHOD_NAME]`
- **Description**: [What this method does]
- **Parameters**: 
  - `[param1]`: [type] - [description]
  - `[param2]`: [type] - [description] (optional)
- **Return Type**: `Future<[return_type]>`

## Implementation Checklist

### 1. Dart Implementation (`lib/mixpanel_flutter.dart`)

Add the method with input validation:
```dart
/// [Method description]
Future<void> [methodName]([parameters]) async {
  // Validate string inputs
  if (_MixpanelHelper.isValidString([stringParam])) {
    Map<String, dynamic> properties = <String, dynamic>{
      'param1': value1,
      'param2': value2 ?? {}, // Use ?? {} for optional maps
    };
    
    await _channel.invokeMethod<void>('[methodName]', properties);
  } else {
    developer.log('`[methodName]` failed: [param] cannot be blank', name: 'Mixpanel');
  }
}
```

### 2. Android Implementation (`android/src/main/java/com/mixpanel/mixpanel_flutter/MixpanelFlutterPlugin.java`)

Add case in `onMethodCall`:
```java
case "[methodName]":
    // Extract parameters
    String param1 = call.argument("param1");
    Map<String, Object> param2 = call.argument("param2");
    
    // Convert properties if needed
    JSONObject jsonProps = MixpanelHelper.convertToJSONObject(param2);
    
    // Call native SDK method
    mixpanel.[nativeMethodName](param1, jsonProps);
    result.success(null);
    break;
```

### 3. iOS Implementation (`ios/Classes/SwiftMixpanelFlutterPlugin.swift`)

Add case in `handle(_ call:)`:
```swift
case "[methodName]":
    guard let args = call.arguments as? [String: Any],
          let param1 = args["param1"] as? String else {
        result(FlutterError(code: "ARGUMENT_ERROR", 
                           message: "Invalid arguments", 
                           details: nil))
        return
    }
    
    let param2 = args["param2"] as? [String: Any] ?? [:]
    
    // Convert properties if needed
    let mixpanelProps = MixpanelTypeHandler.processProperties(param2)
    
    // Call native SDK method
    Mixpanel.mainInstance().[nativeMethodName](param1, properties: mixpanelProps)
    result(nil)
```

### 4. Web Implementation (`lib/mixpanel_flutter_web.dart`)

Add method implementation:
```dart
@override
Future<void> [methodName]([parameters]) async {
  if (!_MixpanelHelper.isValidString([stringParam])) {
    developer.log('`[methodName]` failed: [param] cannot be blank', name: 'Mixpanel');
    return;
  }
  
  Map<String, dynamic>? properties = _getProperties(param2);
  
  // Add library metadata
  properties ??= {};
  properties['\$lib_version'] = MixpanelFlutterLibraryVersion.version;
  properties['mp_lib'] = 'flutter';
  
  // Call JavaScript SDK
  mixpanel.[jsMethodName](param1, safeJsify(properties));
}
```

### 5. Tests (`test/mixpanel_flutter_test.dart`)

Add comprehensive tests:
```dart
group('[methodName]', () {
  test('calls platform method with correct arguments', () async {
    await mixpanel.[methodName]('param1', {'key': 'value'});
    
    expect(
      methodCall,
      isMethodCall(
        '[methodName]',
        arguments: <String, dynamic>{
          'param1': 'param1',
          'param2': {'key': 'value'},
        },
      ),
    );
  });
  
  test('handles null/empty parameters gracefully', () async {
    await mixpanel.[methodName]('', null);
    
    expect(methodCall, isNull);
  });
  
  test('validates required string parameters', () async {
    await mixpanel.[methodName](null, {'key': 'value'});
    
    expect(methodCall, isNull);
  });
});
```

### 6. Example App Usage (`example/lib/`)

Add example usage to demonstrate the feature:
```dart
// In appropriate example page
ElevatedButton(
  onPressed: () async {
    await _mixpanel.[methodName](
      'example_param',
      {
        'property1': 'value1',
        'property2': 123,
        'property3': true,
      },
    );
    _showMessage('[MethodName] completed');
  },
  child: Text('[Method Display Name]'),
),
```

### 7. Documentation Updates

Update the README.md with the new method:
```markdown
### [methodName]

[Description of what the method does]

```dart
await mixpanel.[methodName]('param1', {'key': 'value'});
```
```

### 8. Type Handling Considerations

- **DateTime**: Automatically handled by `MixpanelMessageCodec`
- **Uri**: Automatically handled by `MixpanelMessageCodec`
- **Complex objects**: Convert to `Map<String, dynamic>` first
- **Web platform**: Use `safeJsify()` for JavaScript compatibility

## Validation Checklist

Before submitting:
- [ ] Method follows camelCase naming convention
- [ ] Platform channel method names match exactly across all platforms
- [ ] Input validation prevents crashes
- [ ] Methods fail silently with logging (no exceptions to caller)
- [ ] Library metadata (`$lib_version`, `mp_lib`) included in events
- [ ] Tests cover happy path and edge cases
- [ ] Example app demonstrates usage
- [ ] Code formatted with `dart format .`
- [ ] No analyzer warnings with `flutter analyze`

## Common Patterns

### For methods that track events:
- Always validate event names
- Merge properties with library metadata
- Use `_baseProperties()` for common properties

### For methods with optional parameters:
- Use `??` operator for defaults
- Document default behavior
- Test both with and without optional params

### For methods returning values:
- Specify generic type in `invokeMethod<T>`
- Handle null returns appropriately
- Add return type tests

## Testing the Implementation

1. Run unit tests: `flutter test`
2. Test on each platform:
   ```bash
   cd example
   flutter run -d android
   flutter run -d ios
   flutter run -d chrome
   ```
3. Verify in native platform logs that methods are called correctly
4. Check that events appear in Mixpanel dashboard (if applicable)

## Example Usage

To use this prompt:
1. Replace all `[METHOD_NAME]`, `[methodName]`, etc. with your actual method name
2. Fill in parameter details and descriptions
3. Follow the implementation steps in order
4. Use the validation checklist before submitting

Example filled prompt:
```
Method Name: trackPurchase
Description: Track a purchase event with transaction details
Parameters:
  - productId: String - The ID of the product purchased
  - amount: double - The purchase amount
  - properties: Map<String, dynamic>? - Additional event properties (optional)
Return Type: Future<void>
```