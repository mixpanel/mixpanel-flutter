# Workflow: Release Process

## Overview
The SDK uses an automated release process with version management script and GitHub Actions.

## Prerequisites
- Clean working directory (all changes committed)
- Python installed for release script
- Access to publish on pub.dev
- GitHub repository access for tagging

## Version Bump Process

### 1. **Run Release Script**
```bash
python tool/release.py --old 2.4.3 --new 2.4.4
```

This script automatically:
- Updates version in `pubspec.yaml`
- Updates `$lib_version` in `lib/mixpanel_flutter.dart`
- Updates test expectations in `test/mixpanel_flutter_test.dart`
- Updates version in `ios/mixpanel_flutter.podspec`
- Generates documentation with `dartdoc`
- Commits changes with message "Version X.Y.Z"
- Creates git tag `vX.Y.Z`
- Runs `dart pub publish --dry-run` for validation

### 2. **Files Updated by Script**

#### pubspec.yaml
```yaml
name: mixpanel_flutter
description: Official Mixpanel Flutter SDK
version: 2.4.4  # Updated
```

#### lib/mixpanel_flutter.dart
```dart
static Map<String, String> _getMixpanelProperties() {
  return <String, String>{
    '\$lib_version': '2.4.4',  # Updated
    'mp_lib': 'flutter',
  };
}
```

#### test/mixpanel_flutter_test.dart
```dart
expect(versionRegex.hasMatch('2.4.4'), true);  # Updated
```

#### ios/mixpanel_flutter.podspec
```ruby
Pod::Spec.new do |s|
  s.name             = 'mixpanel_flutter'
  s.version          = '2.4.4'  # Updated
  # ...
end
```

## Manual Release Steps

### 1. **Update CHANGELOG.md**
Add release notes following the existing format:
```markdown
## 2.4.4
* Fixed issue with DateTime serialization on Android
* Added support for new tracking features
* Updated dependencies
```

### 2. **Push Changes**
```bash
git push origin main
git push origin v2.4.4
```

### 3. **GitHub Release**
The push of the version tag triggers GitHub Actions:
- Creates GitHub release automatically
- Generates release notes from commits
- Updates CHANGELOG.md via workflow

### 4. **Publish to pub.dev**
```bash
dart pub publish
```

Follow the prompts to authenticate and confirm publication.

## Version Numbering

Follow semantic versioning:
- **MAJOR**: Breaking API changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, backwards compatible

Examples:
- `2.4.3` → `2.4.4`: Bug fix
- `2.4.3` → `2.5.0`: New feature
- `2.4.3` → `3.0.0`: Breaking change

## Pre-Release Checklist

- [ ] All tests pass: `flutter test`
- [ ] Static analysis clean: `flutter analyze`
- [ ] Example app works on all platforms
- [ ] CHANGELOG.md updated with changes
- [ ] Documentation updated if needed
- [ ] Version compatibility verified:
  - Dart SDK constraints
  - Flutter SDK constraints
  - Native SDK versions

## GitHub Actions Release Workflow

Located in `.github/workflows/release.yml`:

```yaml
name: Release

on:
  release:
    types: [published]

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: release-drafter/release-drafter@v5
        with:
          config-name: release-drafter.yml
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Configuration in `.github/release-drafter.yml`:
- Categorizes changes by labels
- Generates release notes
- Updates CHANGELOG.md

## Rollback Process

If issues are discovered after release:

### 1. **Revert Tag**
```bash
git tag -d v2.4.4
git push origin :refs/tags/v2.4.4
```

### 2. **Fix Issues**
Make necessary fixes and test thoroughly.

### 3. **Re-release**
Either use same version or bump patch version:
```bash
python tool/release.py --old 2.4.4 --new 2.4.5
```

## Platform-Specific Considerations

### iOS CocoaPods
The podspec version must match the pubspec version.

### Android
No special version handling needed beyond pubspec.

### Web
JavaScript library version is determined by CDN link in user's HTML.

## Post-Release Verification

### 1. **Verify pub.dev**
Check that package appears on: https://pub.dev/packages/mixpanel_flutter

### 2. **Test Installation**
Create new Flutter project and add dependency:
```yaml
dependencies:
  mixpanel_flutter: ^2.4.4
```

### 3. **Verify Example App**
```bash
cd example
flutter pub upgrade
flutter run
```

## Common Issues

### Dry Run Failures
If `dart pub publish --dry-run` fails:
- Check for uncommitted changes
- Verify all required files are included
- Check pubspec.yaml formatting

### Version Mismatch
Ensure all version references are updated:
- pubspec.yaml
- lib/mixpanel_flutter.dart
- test/mixpanel_flutter_test.dart
- ios/mixpanel_flutter.podspec

### Tag Already Exists
```bash
# Delete local and remote tag
git tag -d v2.4.4
git push origin :refs/tags/v2.4.4
# Re-run release script
```