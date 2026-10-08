import 'internal/platform/platform_info.dart';

/// SDK version constant. Update this alongside pubspec.yaml when releasing.
const String sdkVersion = '1.2.0';

/// Library identity shared by settings and replay upload requests.
/// Keep web on flutter-sr until the backend supports flutter-sr-web.
const String sdkLibrary = 'flutter-sr';

/// Operating system name for query parameters ($os).
/// Computed once at startup since it never changes.
final String operatingSystem = operatingSystemName;
