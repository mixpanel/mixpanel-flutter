import 'package:web/web.dart' as web;

import 'browser_os.dart';

String get operatingSystemName =>
    browserOperatingSystem(web.window.navigator.userAgent);

bool get isMacOsWithoutSandbox => false;
