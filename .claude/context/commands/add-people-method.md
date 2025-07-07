---
description: Add a new method to the People class for user profile management
---

Create a new People method called ${input:methodName} for ${input:purpose}.

## Implementation Steps

1. **Add to People class** (`lib/mixpanel_flutter.dart`):
```dart
class People {
  Future<void> ${input:methodName}(${input:parameters}) async {
    return await _channel.invokeMethod<void>('people.${input:methodName}', 
      <String, dynamic>{
        ${input:arguments}
      });
  }
}
```

2. **Add to Web People implementation** (`lib/mixpanel_flutter_web.dart`):
```dart
@override
Future<void> ${input:methodName}(${input:parameters}) async {
  var properties = safeJsify(${input:propertiesParam});
  mixpanelJs.people.${input:jsMethodName}(properties);
}
```

3. **Update JavaScript bindings** if needed (`lib/web/mixpanel_js_bindings.dart`):
```dart
@JS()
@anonymous
abstract class People {
  external void ${input:jsMethodName}(dynamic properties);
}
```

4. **Add Android handler** for "people.${input:methodName}":
```java
case "people.${input:methodName}":
    JSONObject properties = MixpanelFlutterHelper.toJSONObject(
        call.argument("properties"));
    mixpanel.getPeople().${input:androidMethod}(properties);
    result.success(null);
    break;
```

5. **Add iOS handler** for "people.${input:methodName}":
```swift
case "people.${input:methodName}":
    if let properties = arguments["properties"] as? [String: Any] {
        let mpProperties = convertToMixpanelTypes(properties)
        Mixpanel.mainInstance().people.${input:iosMethod}(mpProperties)
    }
    result(nil)
```

6. **Add test**:
```dart
test('people.${input:methodName}', () async {
  await mixpanel.getPeople().${input:methodName}(${input:testArgs});
  expect(
    methodCall,
    isMethodCall(
      'people.${input:methodName}',
      arguments: <String, dynamic>{
        ${input:expectedTestArgs}
      },
    ),
  );
});
```

Common People methods follow patterns:
- `set`: Set properties, overwriting existing
- `setOnce`: Set only if not already set
- `increment`: Increment numeric properties
- `append`: Append to list properties
- `union`: Add unique values to list properties