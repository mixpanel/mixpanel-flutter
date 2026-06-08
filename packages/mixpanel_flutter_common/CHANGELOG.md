# Changelog

## [common-v1.0.0](https://github.com/mixpanel/mixpanel-flutter/tree/common-v1.0.0)

Initial public release.

### Features

- **`MixpanelEventBridge`** — process-wide broadcast stream of tracked Mixpanel events. Populated by `mixpanel_flutter`'s native plugins; consumed by downstream packages (session replay, custom trigger logic).
- **`MixpanelEvent`** — event payload type delivered through the bridge.
- **JSONLogic evaluator** — `JsonLogicParser` and `JsonLogicEvaluator` for the subset of [json-logic](https://jsonlogic.com) expressions used by server-configured Event Triggers. Aligned with the equivalent evaluators in `mixpanel-android` and `mixpanel-swift`.
- **`JsonLogicException`** hierarchy — typed exceptions for malformed input, type mismatches, and unsupported operators.
