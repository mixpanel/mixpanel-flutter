@Timeout(Duration(minutes: 20))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'compression_integration_test.dart' as compression;
import 'gzip_integration_test.dart' as gzip;
import 'sqlite_integration_test.dart' as sqlite;
import 'flush_integration_test.dart' as flush;
import 'end_to_end_test.dart' as end_to_end;
import 'lifecycle_integration_test.dart' as lifecycle;
import 'settings_integration_test.dart' as settings;
import 'settings_live_test.dart' as settings_live;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  compression.main();
  gzip.main();
  sqlite.main();
  flush.main();
  end_to_end.main();
  lifecycle.main();
  settings.main();
  settings_live.main();
}
