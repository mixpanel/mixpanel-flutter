@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';

import 'helpers/web_request_identity_checks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'should omit the OS from settings and record when the browser is unknown',
    () async {
      await checkWebRequestIdentity('UnknownBrowser/1.0', null);
    },
  );
}
