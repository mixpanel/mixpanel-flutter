/// Shared pure-Dart support for the Mixpanel Flutter SDK family.
///
/// Two pieces:
/// 1. [MixpanelEventBridge] — process-wide stream of tracked events,
///    populated by `mixpanel_flutter`'s native plugins. Consume this in
///    session replay, custom trigger logic, etc.
/// 2. JSONLogic — parser and evaluator for the Event Trigger rule subset
///    aligned across mixpanel-android, mixpanel-swift, and this package.
library mixpanel_flutter_common;

export 'src/event_bridge.dart';
export 'src/mixpanel_event.dart';
export 'src/jsonlogic/json_logic_evaluator.dart';
export 'src/jsonlogic/json_logic_exception.dart';
export 'src/jsonlogic/json_logic_parser.dart';
export 'src/jsonlogic/json_logic_rule.dart';
