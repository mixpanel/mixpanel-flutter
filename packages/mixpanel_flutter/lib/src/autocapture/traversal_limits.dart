import 'dart:developer' as developer;

const maxNodes = 2000;
const maxDepth = 512;

bool _reportedLimit = false;

/// One generic diagnostic per process; never include tree/content details.
void reportTraversalLimit() {
  if (_reportedLimit) return;
  _reportedLimit = true;
  developer.log(
      'Autocapture traversal budget exceeded; affected signals are skipped.',
      name: 'Mixpanel');
}
