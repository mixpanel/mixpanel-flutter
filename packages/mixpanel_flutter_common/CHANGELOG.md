# Changelog

## [common-v1.0.0](https://github.com/mixpanel/mixpanel-flutter/tree/common-v1.0.0) (2026-06-08)

Initial public release.

### Features

- **`MixpanelEventBridge`** — process-wide broadcast stream of tracked Mixpanel events. Populated by `mixpanel_flutter`; all members are `@internal`, reserved for Mixpanel-authored downstream packages (e.g. `mixpanel_flutter_session_replay`).
- **`MixpanelEvent`** — event payload type delivered through the bridge.
- **JSONLogic evaluator** — `JsonLogicParser` and `JsonLogicEvaluator` for the subset of [json-logic](https://jsonlogic.com) expressions used by Mixpanel server-configured Event Triggers. Behavior is aligned with the Android and iOS Mixpanel SDKs.
- **`JsonLogicException`** hierarchy — typed exceptions for malformed input, type mismatches, and unsupported operators.
