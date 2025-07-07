---
description: Add a new tracking method to the Mixpanel SDK
---

Create a new tracking method called ${input:methodName} that accepts ${input:parameters}.

## Implementation Steps

1. **Add to Dart API** (`lib/mixpanel_flutter.dart`):
```dart
Future<void> ${input:methodName}(${input:dartParameters}) async {
  if (_MixpanelHelper.isValidString(${input:primaryParam})) {
    await _channel.invokeMethod<void>('${input:methodName}', <String, dynamic>{
      ${input:channelArguments}
    });
  } else {
    developer.log('`${input:methodName}` failed: ${input:primaryParam} cannot be blank', 
        name: 'Mixpanel');
  }
}
```

2. **Add to Web implementation** (`lib/mixpanel_flutter_web.dart`):
```dart
@override
Future<void> ${input:methodName}(${input:dartParameters}) async {
  ${input:webImplementation}
}
```

3. **Add Android handler** in `MixpanelFlutterPlugin.java`:
```java
case "${input:methodName}":
    ${input:androidExtractArgs}
    try {
        ${input:androidImplementation}
        result.success(null);
    } catch (JSONException e) {
        result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
    }
    break;
```

4. **Add iOS handler** in `SwiftMixpanelFlutterPlugin.swift`:
```swift
case "${input:methodName}":
    ${input:iosGuardStatement}
    ${input:iosImplementation}
    result(nil)
```

5. **Add test** in `test/mixpanel_flutter_test.dart`:
```dart
test('${input:methodName}', () async {
  await mixpanel.${input:methodName}(${input:testArguments});
  expect(
    methodCall,
    isMethodCall(
      '${input:methodName}',
      arguments: <String, dynamic>{
        ${input:testExpectedArgs}
      },
    ),
  );
});
```

6. **Add to example app** with a button demonstrating the feature.

Remember to:
- Include library metadata in properties
- Handle null/empty validation
- Keep method names consistent across platforms
- Update documentation