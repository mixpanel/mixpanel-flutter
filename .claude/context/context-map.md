# Claude Code Context Map

## Quick Reference

### Common Tasks
- **Adding a new tracking method?** Start with `workflows/new-feature.md`
- **Writing tests?** Check `workflows/testing.md`
- **Preparing a release?** Follow `workflows/release.md`
- **Understanding the architecture?** Read `architecture/system-design.md`
- **Platform-specific implementation?** See relevant technology guides

### Key Commands
- **Add tracking method**: Use `.claude/context/commands/add-tracking-method.md`
- **Add People method**: Use `.claude/context/commands/add-people-method.md`

## File Directory

| File | Purpose | When to Use |
|------|---------|-------------|
| **CLAUDE.md** | Core patterns & quick reference | Always loaded, check first |
| **codebase-map.md** | Project structure overview | Understanding file layout |
| **discovered-patterns.md** | All coding patterns & conventions | Writing new code |
| **architecture/system-design.md** | System architecture & data flow | Understanding how components interact |
| **technologies/flutter-plugin.md** | Flutter plugin development patterns | Working with plugin architecture |
| **technologies/platform-channels.md** | Platform channel details | Implementing native communication |
| **technologies/javascript-interop.md** | Web platform implementation | Working on web support |
| **workflows/new-feature.md** | Step-by-step feature addition | Adding new SDK capabilities |
| **workflows/testing.md** | Testing patterns & practices | Writing or running tests |
| **workflows/release.md** | Release process & versioning | Publishing new versions |
| **commands/*.md** | Reusable code generation | Quick implementations |

## Architecture Overview

```
Dart API Layer (mixpanel_flutter.dart)
    ↓
Platform Channel (with MixpanelMessageCodec)
    ↓
┌─────────────┬──────────────┬────────────────┐
│   Android   │     iOS      │      Web       │
│    (Java)   │   (Swift)    │ (JS Interop)   │
└─────────────┴──────────────┴────────────────┘
    ↓              ↓               ↓
Native SDKs    Native SDKs    Mixpanel.js
```

## Key Patterns Summary

### Input Validation
```dart
if (_MixpanelHelper.isValidString(param)) {
  // proceed with platform call
} else {
  developer.log('failed: param cannot be blank', name: 'Mixpanel');
}
```

### Platform Channel Invocation
```dart
await _channel.invokeMethod<void>('methodName', <String, dynamic>{
  'param1': value1,
  'param2': value2 ?? {},
});
```

### Type Conversion
- Mobile: Custom `MixpanelMessageCodec` handles DateTime/Uri
- Web: Use `safeJsify()` for JavaScript compatibility

## Development Workflow

1. **Setup**: `flutter pub get`
2. **Development**: Make changes following patterns
3. **Testing**: `flutter test` and example app testing
4. **Release**: `python tool/release.py --old X.Y.Z --new A.B.C`

## Platform Requirements

- **Android**: API 21+ (Android 5.0)
- **iOS**: iOS 12.0+
- **Web**: Modern browsers with JavaScript enabled

## Maintenance Guide

### When to Update Context
- New patterns emerge in codebase
- Architecture changes
- New workflows established
- Platform requirements change

### How to Update
1. Edit relevant files in `.claude/context/`
2. Update `CLAUDE.md` if it's a core pattern
3. Test that documentation matches reality
4. Commit context updates with code changes

## Quick Debugging

### Common Issues
- **Empty string validation**: Methods silently fail with logging
- **Type serialization**: Check codec implementations
- **Platform differences**: Compare implementations across platforms
- **Web initialization**: Ensure mixpanel.js is loaded

### Where to Look
- **Dart errors**: Check validation and channel invocation
- **Android errors**: `MixpanelFlutterPlugin.java` and helper
- **iOS errors**: `SwiftMixpanelFlutterPlugin.swift` and type handler
- **Web errors**: `mixpanel_flutter_web.dart` and JS bindings

## Contact & Resources

- **Official Docs**: https://developer.mixpanel.com/docs/flutter
- **GitHub**: https://github.com/mixpanel/mixpanel-flutter
- **Example App**: `/example` directory for working code
- **Tests**: `/test` directory for test patterns