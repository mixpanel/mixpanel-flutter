import 'package:flutter/foundation.dart' show kIsWeb;

import 'internal/platform/platform_info.dart';

/// SDK version constant. Update this alongside pubspec.yaml when releasing.
const String sdkVersion = '2.1.0';

/// Library identity shared by settings and replay upload requests.
/// Web replays report separately so the backend can tell them from native.
const String sdkLibrary = kIsWeb ? 'flutter-web-sr' : 'flutter-sr';

/// Operating system name for query parameters ($os).
/// Computed once at startup since it never changes.
final String operatingSystem = operatingSystemName;
