##### _June 8, 2026_ - [common-v1.0.0](https://github.com/mixpanel/mixpanel-flutter/releases/tag/common-v1.0.0)

# mixpanel_flutter_common

Shared pure-Dart support for the Mixpanel Flutter SDK family.

This package is a building block consumed by other Mixpanel packages —
primarily [`mixpanel_flutter`](https://pub.dev/packages/mixpanel_flutter)
and `mixpanel_flutter_session_replay`. Most app developers should depend
on `mixpanel_flutter` directly; depend on this package only if you are
building a Mixpanel-compatible library that needs the shared event bridge
or JSONLogic evaluator.

# Contents

- **`MixpanelEventBridge`** — a process-wide broadcast stream of tracked
  events. `mixpanel_flutter` populates the stream; Mixpanel-authored
  downstream packages such as `mixpanel_flutter_session_replay` subscribe
  to it to react to events without re-instrumenting `track()` call sites.
- **`MixpanelEvent`** — the event payload delivered through the bridge.
- **JSONLogic evaluator** — `JsonLogicParser` + `JsonLogicEvaluator` for
  the subset of [json-logic](https://jsonlogic.com) expressions used by
  Mixpanel server-configured Event Triggers. Behavior is aligned with the
  Android and iOS Mixpanel SDKs so trigger evaluation is consistent across
  platforms.

# Install

```
   dependencies:
      mixpanel_flutter_common: 1.0.0
```

```
   $ flutter pub get
```

```dart
import 'package:mixpanel_flutter_common/mixpanel_flutter_common.dart';
```

# Public API surface

The exported library is intentionally narrow.

### Application API

| Symbol | Use |
|---|---|
| `MixpanelEvent` | Event payload type |
| `JsonLogicRule` | Opaque token returned by the parser and consumed by the evaluator |
| `JsonLogicParser.parse(String)` | Parse a JSONLogic JSON string into a rule |
| `JsonLogicEvaluator.evaluate(rule, data)` | Evaluate a rule against a property map |
| `JsonLogicException` and concrete subtypes | Thrown by the parser/evaluator on malformed input |

The concrete rule subclasses (`AndRule`, `VarRule`, `LiteralRule`, etc.)
are AST implementation details and are intentionally not exported.
Treat `JsonLogicRule` as an opaque value: get one from the parser, pass
it to the evaluator.

### `MixpanelEventBridge` — reserved for Mixpanel-authored packages

All members on `MixpanelEventBridge` (`events`, `notifyListeners`,
`setLifecycleCallbacks`, `setSourceWiringHook`) are annotated `@internal`.
They form the cross-package coordination surface used by `mixpanel_flutter`
(to forward tracked events into Dart) and by downstream packages such as
`mixpanel_flutter_session_replay` (to subscribe to events and inject
fakes from tests). Application code should rely on the public
`mixpanel_flutter` SDK APIs instead of subscribing to this stream directly.

# Versioning

This package follows [semver](https://semver.org/). Breaking changes to
the public API surface listed above will only land in a major version
bump.

# Releases

This package ships independently from `mixpanel_flutter`. Tags use the
`common-v<version>` prefix (e.g. `common-v1.0.0`). The `mixpanel_flutter`
package continues to use the bare `v<version>` prefix.

# License

[Apache 2.0](./LICENSE) — same as the rest of the Mixpanel Flutter SDK family.
