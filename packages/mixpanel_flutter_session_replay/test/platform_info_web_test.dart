@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers/web_request_identity_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('settings and record identify Flutter web and the browser OS', () async {
    await checkWebRequestIdentity(
      'Mozilla/5.0 (Linux; Android 15; Pixel 9)',
      'Android',
    );
  });
}
