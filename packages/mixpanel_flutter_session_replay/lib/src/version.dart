import 'internal/platform/platform_info.dart';

/// SDK version constant. Update this alongside pubspec.yaml when releasing.
const String sdkVersion = '1.1.1';

/// Operating system name for query parameters ($os).
/// Computed once at startup since it never changes.
final String operatingSystem = operatingSystemName;
