# Discovered Patterns

## Naming Conventions

### Method Naming
All methods use camelCase with consistent verb prefixes:
```dart
// Tracking methods use 'track' prefix
track(String eventName)
trackWithGroups(String eventName, Map<String, Object> properties)

// Registration methods use 'register' prefix
registerSuperProperties(Map<String, dynamic> properties)
registerSuperPropertiesOnce(Map<String, dynamic> properties)

// Getter methods use 'get' prefix
getPeople()
getGroup(String groupKey, dynamic groupID)
```

### Parameter Naming
Properties always use consistent naming patterns:
```dart
// Properties maps are always named 'properties' or with specific prefix
Map<String, dynamic> properties
Map<String, dynamic> superProperties

// IDs use descriptive suffixes
String distinctId
dynamic groupID
String eventName
```

### File Organization
Files follow snake_case convention with clear purpose:
- `mixpanel_flutter.dart` - Main API surface
- `mixpanel_flutter_web.dart` - Web-specific implementation
- `mixpanel_message_codec.dart` - Custom serialization

## Code Organization

### Platform Channel Pattern
All platform communication uses a standardized channel approach:
```dart
// From lib/mixpanel_flutter.dart
static final MethodChannel _channel = kIsWeb
    ? const MethodChannel('mixpanel_flutter')
    : const MethodChannel(
        'mixpanel_flutter', StandardMethodCodec(MixpanelMessageCodec()));

// Standard invocation pattern
Future<void> track(String eventName,
    {Map<String, dynamic>? properties}) async {
  if (_MixpanelHelper.isValidString(eventName)) {
    await _channel.invokeMethod<void>('track', <String, dynamic>{
      'eventName': eventName,
      'properties': properties ?? {},
    });
  } else {
    developer.log('`track` failed: eventName cannot be blank',
        name: 'Mixpanel');
  }
}
```

### Singleton Initialization Pattern
The SDK uses static initialization with factory pattern:
```dart
// From lib/mixpanel_flutter.dart
static Future<Mixpanel> init(String token,
    {bool optOutTrackingDefault = false,
    required bool trackAutomaticEvents,
    Map<String, dynamic>? superProperties,
    Map<String, dynamic>? config}) async {
  var mixpanelProperties = _getMixpanelProperties();

  await _channel.invokeMethod<void>('initialize', <String, dynamic>{
    'token': token,
    'optOutTrackingDefault': optOutTrackingDefault,
    'trackAutomaticEvents': trackAutomaticEvents,
    'superProperties': superProperties ?? {},
    'properties': mixpanelProperties,
    'config': config ?? {},
  });

  return Mixpanel(token);
}
```

## Error Handling

### Input Validation Pattern
All public methods validate inputs before platform calls:
```dart
// From lib/mixpanel_flutter.dart
if (_MixpanelHelper.isValidString(alias)) {
  _channel.invokeMethod<void>('alias', <String, dynamic>{
    'alias': alias,
    'distinctId': distinctId,
  });
} else {
  developer.log('`alias` failed: alias cannot be blank', name: 'Mixpanel');
}
```

### Platform-Specific Error Handling
Each platform handles errors appropriately:
```java
// From android/src/.../MixpanelFlutterPlugin.java
try {
  properties = MixpanelFlutterHelper.getMergedProperties(properties, mixpanelProperties);
} catch (JSONException e) {
  result.error("MixpanelFlutterException", e.getLocalizedMessage(), null);
  return;
}
```

```swift
// From ios/Classes/SwiftMixpanelFlutterPlugin.swift
guard let properties = arguments["properties"] as? [String: Any] else {
  result(nil)
  return
}
```

## Type Handling Patterns

### Custom Message Codec
Complex types require special handling across platforms:
```dart
// From lib/codec/mixpanel_message_codec.dart
class MixpanelMessageCodec extends StandardMessageCodec {
  const MixpanelMessageCodec();

  @override
  void writeValue(WriteBuffer buffer, dynamic value) {
    if (value is DateTime) {
      buffer.putUint8(_typeDateTime);
      buffer.putInt64(value.millisecondsSinceEpoch);
    } else if (value is Uri) {
      buffer.putUint8(_typeUri);
      writeValue(buffer, value.toString());
    } else {
      super.writeValue(buffer, value);
    }
  }
}
```

### Web-Specific Type Conversion
Web platform uses safe JavaScript conversion:
```dart
// From lib/mixpanel_flutter_web.dart
dynamic safeJsify(Object value) {
  if (value is Map<dynamic, dynamic>) {
    value = JsLinkedHashMap.from(value);
  }
  var args = jsify(value);
  return args;
}
```

## Testing Patterns

### Mock Channel Testing
Tests verify correct method calls and arguments:
```dart
// From test/mixpanel_flutter_test.dart
test('track', () async {
  await mixpanel.track('test event', properties: {'a': 'b'});
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
```

### Validation Testing
Tests ensure invalid inputs are handled:
```dart
test('track() should not crash when event name is empty', () async {
  await mixpanel.track('', properties: {'a': 'b'});
  expect(methodCall, null);
});
```

## Documentation Patterns

### API Documentation Style
Public methods use comprehensive documentation:
```dart
/// Track an event.
///
/// Every call to track eventually results in a data point sent to Mixpanel.
/// These data points are what are measured, counted, and broken down to create
/// your Mixpanel reports. Events have a string name, and an optional set of
/// name/value pairs that describe the properties of that event.
///
/// * [eventName] The name of the event to send
/// * [properties] A Map containing the key value pairs of the properties
///  to include in this event. Pass null if no extra properties exist.
```

### Parameter Documentation
Parameters are documented with specific format:
```dart
/// * [distinctId] a string uniquely identifying this user. Events sent to
///   Mixpanel using the same distinct id will be considered associated with the
///   same visitor/customer for retention and funnel reporting...
```

## Async Patterns

### Consistent Future Returns
All methods return Future<void> for consistency:
```dart
Future<void> identify(String distinctId) async {
  if (_MixpanelHelper.isValidString(distinctId)) {
    return await _channel.invokeMethod<void>('identify', <String, dynamic>{
      'distinctId': distinctId,
    });
  }
}
```

### Fire-and-Forget Pattern
Most tracking calls don't await responses:
```dart
// Caller typically uses without await
mixpanel.track('Button Clicked');

// But can await if needed for sequencing
await mixpanel.track('Purchase Complete');
await mixpanel.flush();
```

## Platform Detection

### Runtime Platform Checks
Uses Flutter's platform detection utilities:
```dart
// Web detection
import 'package:flutter/foundation.dart' show kIsWeb;

// Platform-specific behavior
if (kIsWeb) {
  // Web-specific implementation
} else {
  // Mobile implementation
}
```

## Version Management

### Hardcoded Version Tracking
SDK version included in tracking properties:
```dart
static Map<String, String> _getMixpanelProperties() {
  return <String, String>{
    '\$lib_version': '2.4.4',
    // Other properties...
  };
}
```