@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/platform/platform_init.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';

import 'helpers/in_memory_event_queue.dart';

void main() {
  test(
    'web initialization preserves queued events when no session can resume',
    () async {
      final queue = InMemoryEventQueue();
      await queue.initialize();
      final session = Session(
        id: 'upload-backlog',
        startTime: DateTime.utc(2025),
        status: SessionStatus.ended,
      );
      await queue.createSessionMetadata(session);
      await queue.add(
        SessionReplayEvent(
          sessionId: session.id,
          distinctId: 'user-1',
          timestamp: DateTime.utc(2025),
          type: EventType.metadata,
          payload: MetadataPayload(width: 100, height: 200),
        ),
      );

      final result = await platformInit(
        token: 'test-token',
        storageQuotaMB: 50,
        directive: MaskingDirective(autoMaskTypes: const {}),
        debugOverlayEnabled: false,
        mobileWifiOnly: false,
        webIdleTimeout: const Duration(minutes: 30),
        webMaxSessionDuration: const Duration(hours: 24),
        useAccessibilityLabelFallback: false,
        logger: MixpanelLogger(LogLevel.none),
        eventQueue: queue,
      );

      expect(result.resumableSession, isNull);
      expect(queue.eventCount, 1);

      await result.screenshotCapturer.dispose();
      await queue.dispose();
    },
  );
}
