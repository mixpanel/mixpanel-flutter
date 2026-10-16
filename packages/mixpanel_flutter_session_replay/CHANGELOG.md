# Changelog

## [session-replay-v2.1.0](https://github.com/mixpanel/mixpanel-flutter/tree/session-replay-v2.1.0) (2026-10-16)

### Features
- (Beta) Add web support to Session Replay ([#283](https://github.com/mixpanel/mixpanel-flutter/pull/283))

[Full Changelog](https://github.com/mixpanel/mixpanel-flutter/compare/session-replay-v2.0.0...session-replay-v2.1.0)

## [session-replay-v2.0.0](https://github.com/mixpanel/mixpanel-flutter/tree/session-replay-v2.0.0) (2026-10-13)

### Breaking Changes ([#293](https://github.com/mixpanel/mixpanel-flutter/pull/293))
- **iOS 15.0 minimum.** The plugin now requires iOS 15.0 to meet Xcode 27's minimum deployment target. CocoaPods apps must set `platform :ios, '15.0'` in `ios/Podfile`. Need iOS 13–14? Stay on 1.x and build with Xcode 26.
- **macOS 12.0 minimum.** The plugin now requires macOS 12.0. CocoaPods apps must set `platform :osx, '12.0'` in `macos/Podfile`. Need macOS 10.15–11? Stay on 1.x and build with Xcode 26.
- **Building with Xcode 27 requires Flutter 3.47+.** Earlier Flutter versions fail Xcode 27's architecture verification ([flutter/flutter#188461](https://github.com/flutter/flutter/issues/188461)). The package's own Flutter floor is unchanged at 3.38.

[Full Changelog](https://github.com/mixpanel/mixpanel-flutter/compare/session-replay-v1.2.0...session-replay-v2.0.0)

## [session-replay-v1.2.0](https://github.com/mixpanel/mixpanel-flutter/tree/session-replay-v1.2.0) (2026-09-17)

### Features
- update native SDKs for semver and date flag operators ([#281](https://github.com/mixpanel/mixpanel-flutter/pull/281))
- wireframes (beta) ([#278](https://github.com/mixpanel/mixpanel-flutter/pull/278))
- send app bundle_id and build_number as settings API query params ([#279](https://github.com/mixpanel/mixpanel-flutter/pull/279))

### Fixes
- Optimize mask detection traversal ([#280](https://github.com/mixpanel/mixpanel-flutter/pull/280))
- [SDK-127] pin capture identity so a frame cannot land in another user's replay ([#284](https://github.com/mixpanel/mixpanel-flutter/pull/284))

[Full Changelog](https://github.com/mixpanel/mixpanel-flutter/compare/session-replay-v1.1.1...session-replay-v1.2.0)

## [session-replay-v1.1.1](https://github.com/mixpanel/mixpanel-flutter/tree/session-replay-v1.1.1) (2026-07-20)

### Fixes
- Change SPM Package.swift iOS platform version to 13.0 for Session Replay ([#270](https://github.com/mixpanel/mixpanel-flutter/pull/270))

[Full Changelog](https://github.com/mixpanel/mixpanel-flutter/compare/session-replay-v1.1.0...session-replay-v1.1.1)

## [session-replay-v1.1.0](https://github.com/mixpanel/mixpanel-flutter/tree/session-replay-v1.1.0) (2026-07-10)

### Features
- Swift package manager support ([#258](https://github.com/mixpanel/mixpanel-flutter/pull/258))

[Full Changelog](https://github.com/mixpanel/mixpanel-flutter/compare/session-replay-v1.0.0...session-replay-v1.1.0)

## [session-replay-v1.0.0](https://github.com/mixpanel/mixpanel-flutter/tree/session-replay-v1.0.0) (2026-06-22)

* Official v1 release
* No changes from 0.1.0-beta.4

## [v0.1.0-beta.4](https://github.com/mixpanel/mixpanel-flutter-session-replay/tree/v0.1.0-beta.4) (2026-06-12)

### Features
- runtime events ([#38](https://github.com/mixpanel/mixpanel-flutter-session-replay/pull/38))
- Add DataResidency endpoints ([#39](https://github.com/mixpanel/mixpanel-flutter-session-replay/pull/39))

### Fixes
- remove debug overlay when recording is stopped ([#40](https://github.com/mixpanel/mixpanel-flutter-session-replay/pull/40))

[Full Changelog](https://github.com/mixpanel/mixpanel-flutter-session-replay/compare/v0.1.0-beta.3...v0.1.0-beta.4)
## 0.1.0-beta.3

### Features

* remote configuration (#7)

### Bug Fixes

* Don't mask "unmask" debug decisions (#21)

## 0.1.0-beta.2

### Bug Fixes

* correct touch coordinate mapping by removing device frame (#11)

### Other

* Migrate Android Kotlin jvmTarget to compilerOptions DSL for AGP 8.1+ (#17)

## 0.1.0-beta.1

* Initial Beta release
