import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/storage/memory_event_queue.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';

import 'helpers/event_queue_contract_tests.dart';

void main() {
  group('MemoryEventQueue', () {
    late MemoryEventQueue queue;

    setUp(() async {
      queue = MemoryEventQueue(
        quotaMB: 50,
        logger: MixpanelLogger(LogLevel.none),
      );
      await queue.initialize();
    });

    tearDown(() => queue.dispose());

    runEventQueueContractTests(() => queue);
  });
}
