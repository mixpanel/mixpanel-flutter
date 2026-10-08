import 'dart:io' show Platform;

/// Native platform implementation using dart:io.

String get operatingSystemName => switch (Platform.operatingSystem) {
  'android' => 'Android',
  'ios' => 'iOS',
  'macos' => 'Mac OS X',
  _ => Platform.operatingSystem,
};

bool get isMacOsWithoutSandbox =>
    Platform.isMacOS &&
    !Platform.environment.containsKey('APP_SANDBOX_CONTAINER_ID');
