import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/browser_os.dart';

void main() {
  final cases = {
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64)': 'Windows',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)': 'iOS',
    'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)': 'iOS',
    'Mozilla/5.0 (iPod touch; CPU iPhone OS 15_0 like Mac OS X)': 'iOS',
    'Mozilla/5.0 (Linux; Android 15; Pixel 9)': 'Android',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)': 'Mac OS X',
    'Mozilla/5.0 (X11; Linux x86_64)': 'Linux',
    'Mozilla/5.0 (X11; CrOS x86_64 16093.68.0)': 'Chrome OS',
    'UnknownBrowser/1.0': '',
    '': '',
  };
  for (final entry in cases.entries) {
    test('normalizes ${entry.key} to ${entry.value}', () {
      expect(browserOperatingSystem(entry.key), entry.value);
    });
  }
}
