@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers/web_request_identity_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('settings and record omit an unknown browser OS', () async {
    await checkWebRequestIdentity('UnknownBrowser/1.0', null);
  });
}
