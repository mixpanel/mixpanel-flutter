import 'dart:io' show Platform;

/// SDK version constant. Update this alongside pubspec.yaml when releasing.
const String sdkVersion = '1.0.0-flutter';

/// Operating system name for query parameters ($os).
/// Computed once at startup since it never changes.
final String operatingSystem = switch (Platform.operatingSystem) {
  'android' => 'Android',
  'ios' => 'iOS',
  'macos' => 'Mac OS X',
  _ => Platform.operatingSystem,
};
