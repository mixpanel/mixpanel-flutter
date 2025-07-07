# Project Coding Standards for AI Assistance

> These instructions are automatically included in every GitHub Copilot interaction. They represent our most critical patterns and conventions for the Mixpanel Flutter SDK.

## Core Principles

1. **Input Validation First**: All user inputs must be validated before platform channel calls
   - String inputs validated with `_MixpanelHelper.isValidString()`
   - Prevent crashes at the API boundary

2. **Fail Silently with Logging**: Never throw exceptions to calling code
   - Log errors using `developer.log()` with 'Mixpanel' name
   - Return gracefully on validation failures

3. **Platform Channel Consistency**: All native calls follow exact same pattern
   - Method name must match across Dart and native code
   - Arguments always in `Map<String, dynamic>` format

4. **Type Safety**: Handle cross-platform type differences explicitly
   - Mobile: MixpanelMessageCodec handles DateTime/Uri
   - Web: Use `safeJsify()` for JavaScript compatibility

## Flutter SDK Guidelines

### Method Patterns
All public methods MUST follow this exact structure:
```dart
Future<void> methodName(String requiredParam, [Map<String, dynamic>? optionalParam]) async {
  if (!_MixpanelHelper.isValidString(requiredParam)) {
    developer.log('`methodName` failed: requiredParam cannot be blank', name: 'Mixpanel');
    return;
  }
  
  await _channel.invokeMethod<void>('methodName', <String, dynamic>{
    'requiredParam': requiredParam,
    'optionalParam': optionalParam ?? {},
  });
}
```

### Naming Conventions
- **Methods**: camelCase with action verbs (`track`, `registerSuperProperties`, `getPeople`)
- **Parameters**: Descriptive names (`eventName`, `distinctId`, `properties`)
- **Maps**: Always named `properties` or `superProperties` for consistency

### Platform Channel Rules
When invoking platform methods, you MUST:
1. Use exact method name matching between Dart and native
   ```dart
   await _channel.invokeMethod<void>('track', args); // 'track' must exist in native
   ```

2. Structure arguments as flat maps
   ```dart
   <String, dynamic>{
     'eventName': eventName,
     'properties': properties ?? {},
   }
   ```

3. Handle optional parameters with `?? {}`
   ```dart
   'properties': properties ?? {}, // Never pass null
   ```

## Code Generation Rules

When generating code, you MUST:

1. Validate all string inputs before use
   ```dart
   if (!_MixpanelHelper.isValidString(input)) {
     developer.log('`method` failed: input cannot be blank', name: 'Mixpanel');
     return;
   }
   ```

2. Return Future<void> for all public methods
   ```dart
   Future<void> methodName() async {
     // All methods async for platform consistency
   }
   ```

3. Include library metadata in tracking calls
   ```dart
   properties['\$lib_version'] = '2.4.4';
   properties['mp_lib'] = 'flutter';
   ```

When generating code, NEVER:
- Throw exceptions from public methods
- Pass null to platform channels (use `?? {}`)
- Create synchronous public methods
- Skip input validation

## Testing Requirements

Every test must:
- Use descriptive test names: `test('should fail silently when eventName is empty')`
- Verify platform channel calls with `isMethodCall` matcher
- Test both success and validation failure cases

```dart
test('tracks event with properties', () async {
  await mixpanel.track('Event', properties: {'key': 'value'});
  expect(
    methodCall,
    isMethodCall(
      'track',
      arguments: <String, dynamic>{
        'eventName': 'Event',
        'properties': {'key': 'value'},
      },
    ),
  );
});
```

## Documentation Standards

- Public methods need dartdoc with parameter descriptions
- Use `///` for public API documentation
- Include parameter constraints in docs
- No redundant comments in implementation

```dart
/// Tracks an event with optional properties.
///
/// * [eventName] The name of the event to track. Cannot be empty.
/// * [properties] Optional properties to include with the event.
Future<void> track(String eventName, [Map<String, dynamic>? properties]) async {
```

## Security and Performance

ALWAYS:
- Validate inputs at SDK boundaries
- Sanitize data before sending to native platforms
- Log errors without exposing sensitive data

NEVER:
- Log user data or event properties in error messages
- Trust client inputs without validation
- Make synchronous platform channel calls

## Type Handling Matrix

| Type | Mobile | Web |
|------|---------|-----|
| String | Direct pass | Direct pass |
| num/bool | Direct pass | Direct pass |
| DateTime | MixpanelMessageCodec | Convert to ISO string |
| Uri | MixpanelMessageCodec | Convert to string |
| Map | Direct pass | `safeJsify()` |
| List | Direct pass | `safeJsify()` |

## Platform-Specific Patterns

### Web Implementation
```dart
if (kIsWeb) {
  return WebImplementation.method(safeJsify(properties));
}
```

### Mobile Implementation  
```dart
return await _channel.invokeMethod<void>('method', args);
```

## Additional Resources

For architectural questions or complex refactoring needs, Claude Code CLI (`cc`) provides comprehensive context about this SDK's patterns and implementation details.