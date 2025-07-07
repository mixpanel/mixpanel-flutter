# Workflow: Adding a New Feature

## Prerequisites
- Understand the existing SDK architecture
- Have Flutter development environment set up
- Familiar with platform channels and native development

## Steps

### 1. **Define the Dart API**
Add the new method to the appropriate class in `lib/mixpanel_flutter.dart`:

```dart
// For general tracking features
class Mixpanel {
  Future<void> newFeature(String param1, {Map<String, dynamic>? properties}) async {
    if (_MixpanelHelper.isValidString(param1)) {
      await _channel.invokeMethod<void>('newFeature', <String, dynamic>{
        'param1': param1,
        'properties': properties ?? {},
      });
    } else {
      developer.log('`newFeature` failed: param1 cannot be blank', name: 'Mixpanel');
    }
  }
}

// For user-specific features
class People {
  Future<void> newUserFeature(Map<String, dynamic> properties) async {
    return await _channel.invokeMethod<void>('newUserFeature', <String, dynamic>{
      'properties': properties,
    });
  }
}
```

### 2. **Update Web Implementation**
Add the method to `lib/mixpanel_flutter_web.dart`:

```dart
@override
Future<void> newFeature(String param1, Map<String, dynamic> properties) async {
  var jsProperties = safeJsify(properties);
  mixpanelJs.newFeature(param1, jsProperties);
}
```

Update JavaScript bindings in `lib/web/mixpanel_js_bindings.dart` if needed:
```dart
@JS()
@anonymous
abstract class MixpanelJs {
  external void newFeature(String param1, [dynamic properties]);
}
```

### 3. **Implement Android Handler**
Add case to `android/src/main/java/com/mixpanel/mixpanel_flutter/MixpanelFlutterPlugin.java`:

```java
case "newFeature":
    String param1 = call.argument("param1");
    Map<String, Object> properties = call.argument("properties");
    
    try {
        JSONObject jsonProperties = MixpanelFlutterHelper.toJSONObject(properties);
        // Add library metadata
        jsonProperties = MixpanelFlutterHelper.getMergedProperties(jsonProperties, mixpanelProperties);
        
        // Call native SDK
        mixpanel.newFeature(param1, jsonProperties);
        result.success(null);
    } catch (JSONException e) {
        result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
    }
    break;
```

### 4. **Implement iOS Handler**
Add case to `ios/Classes/SwiftMixpanelFlutterPlugin.swift`:

```swift
case "newFeature":
    guard let arguments = call.arguments as? [String: Any],
          let param1 = arguments["param1"] as? String else {
        result(nil)
        return
    }
    
    var properties = Properties()
    if let props = arguments["properties"] as? [String: Any] {
        properties = convertToMixpanelTypes(props)
    }
    
    // Add library metadata
    properties.merge(getMixpanelProperties()) { (_, new) in new }
    
    // Call native SDK
    Mixpanel.mainInstance().newFeature(param1, properties: properties)
    result(nil)
```

### 5. **Add Example Implementation**
Create or update a page in `example/lib/`:

```dart
// In example/lib/new_feature_page.dart
class NewFeaturePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New Feature Example')),
      body: ListView(
        children: [
          MixpanelButton(
            title: 'Test New Feature',
            message: 'Testing new feature with properties',
            onPressed: () {
              mixpanel.newFeature('test-param', properties: {
                'timestamp': DateTime.now(),
                'user_action': 'button_click',
              });
            },
          ),
        ],
      ),
    );
  }
}
```

### 6. **Write Tests**
Add test cases to `test/mixpanel_flutter_test.dart`:

```dart
test('newFeature sends correct parameters', () async {
  await mixpanel.newFeature('test-param', properties: {'key': 'value'});
  expect(
    methodCall,
    isMethodCall(
      'newFeature',
      arguments: <String, dynamic>{
        'param1': 'test-param',
        'properties': <String, dynamic>{'key': 'value'},
      },
    ),
  );
});

test('newFeature validates empty string', () async {
  await mixpanel.newFeature('', properties: {'key': 'value'});
  expect(methodCall, null); // Should not make platform call
});
```

### 7. **Update Documentation**
- Add method documentation with triple-slash comments
- Update CHANGELOG.md with the new feature
- Update README.md if it's a major feature

## Testing Checklist
- [ ] Unit tests pass: `flutter test`
- [ ] Example app works on Android: `cd example && flutter run`
- [ ] Example app works on iOS: `cd example && flutter run`
- [ ] Example app works on Web: `cd example && flutter run -d chrome`
- [ ] Static analysis passes: `flutter analyze`

## Common Pitfalls
- Forgetting to add library metadata ($lib_version) to properties
- Not handling null/empty string validation
- Inconsistent method naming between platforms
- Missing type conversions for complex objects
- Not updating all three platforms (Android, iOS, Web)

## Type Handling
If your feature uses special types:
1. DateTime: Automatically handled by MixpanelMessageCodec
2. Uri: Automatically handled by MixpanelMessageCodec
3. Custom objects: Convert to Map<String, dynamic> first