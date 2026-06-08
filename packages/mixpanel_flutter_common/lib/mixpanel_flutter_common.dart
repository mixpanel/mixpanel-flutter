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
// Only the abstract base type is part of the public surface. Concrete rule
// subclasses (AndRule, VarRule, LiteralRule, etc.) are implementation
// details of the parser/evaluator — consumers receive a JsonLogicRule from
// JsonLogicParser.parse() and pass it straight to JsonLogicEvaluator.evaluate()
// without inspecting or constructing subclasses.
export 'src/jsonlogic/json_logic_rule.dart' show JsonLogicRule;
