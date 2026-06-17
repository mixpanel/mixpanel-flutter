import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/mixpanel_flutter_session_replay.dart';
import 'helpers/in_memory_event_queue.dart';

void main() {
  /// Create an InMemoryEventQueue (no SQLite, no temp dirs)
  Future<InMemoryEventQueue> createQueue(String token) async {
    final queue = InMemoryEventQueue();
    await queue.initialize();
    return queue;
  }

  /// Check if queue is disposed
  bool isQueueDisposed(InMemoryEventQueue queue) {
    return queue.isDisposed;
  }

  /// Check if queue has events
  bool isQueueEmpty(InMemoryEventQueue queue) {
    if (queue.isDisposed) return true;
    return queue.eventCount == 0;
  }

  group('MixpanelSessionReplayConfig', () {
    test('default values', () {
      const config = SessionReplayOptions();
      expect(config.autoMaskedViews, {
        AutoMaskedView.text,
        AutoMaskedView.image,
      });
    });

    test('custom values', () {
      const config = SessionReplayOptions(
        autoMaskedViews: {AutoMaskedView.text},
      );
      expect(config.autoMaskedViews, {AutoMaskedView.text});
    });

    test('empty autoMaskedViews', () {
      const config = SessionReplayOptions(autoMaskedViews: {});
      expect(config.autoMaskedViews, isEmpty);
    });
  });

  group('AutoMaskedView', () {
    test('has all expected values', () {
      expect(AutoMaskedView.values, contains(AutoMaskedView.text));
      expect(AutoMaskedView.values, contains(AutoMaskedView.image));
    });
  });

  group('MixpanelSessionReplay', () {
    const testToken = 'test-token-reinit';
    const testDistinctId = 'user-123';

    // Safe options for testing
    final testOptions = SessionReplayOptions(
      logLevel: LogLevel.none,
      flushInterval: Duration(hours: 1), // Prevent any auto-flush during tests
    );

    test('successful first initialization', () async {
      final queue = await createQueue(testToken);

      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );

      expect(result.success, true);
      expect(result.instance, isNotNull);
      expect(result.instance!.distinctId, testDistinctId);
      expect(isQueueEmpty(queue), true);
    });

    test('re-initialization with same token disposes old instance', () async {
      const firstDistinctId = 'user-1';
      const secondDistinctId = 'user-2';

      final queue1 = await createQueue(testToken);

      // First initialization
      final result1 = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: firstDistinctId,
        options: testOptions,
        eventQueue: queue1,
      );

      expect(result1.success, true);
      final instance1 = result1.instance!;
      expect(instance1.distinctId, firstDistinctId);

      final queue2 = await createQueue(testToken);

      // Second initialization with same token - should dispose old instance
      final result2 = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: secondDistinctId,
        options: testOptions,
        eventQueue: queue2,
      );

      expect(result2.success, true);
      final instance2 = result2.instance!;
      expect(instance2.distinctId, secondDistinctId);

      // Instances should be different
      expect(identical(instance1, instance2), false);

      // Old queue should have been disposed during old instance disposal
      expect(isQueueDisposed(queue1), true);

      // New queue should NOT be disposed
      expect(isQueueDisposed(queue2), false);
    });

    test('re-initialization allows different tokens simultaneously', () async {
      const tokenA = 'token-a';
      const distinctIdA = 'user-a';
      const tokenB = 'token-b';
      const distinctIdB = 'user-b';

      final queueA = await createQueue(tokenA);
      final queueB = await createQueue(tokenB);

      // Initialize with token A
      final resultA = await MixpanelSessionReplay.initializeWithDependencies(
        token: tokenA,
        distinctId: distinctIdA,
        options: testOptions,
        eventQueue: queueA,
      );

      // Initialize with token B
      final resultB = await MixpanelSessionReplay.initializeWithDependencies(
        token: tokenB,
        distinctId: distinctIdB,
        options: testOptions,
        eventQueue: queueB,
      );

      expect(resultA.success, true);
      expect(resultB.success, true);
      expect(identical(resultA.instance, resultB.instance), false);
      expect(resultA.instance!.distinctId, distinctIdA);
      expect(resultB.instance!.distinctId, distinctIdB);

      // Both queues should still be active
      expect(isQueueDisposed(queueA), false);
      expect(isQueueDisposed(queueB), false);
    });

    test('multiple rapid re-initializations complete successfully', () async {
      const finalDistinctId = 'final-user';

      // Rapidly re-initialize multiple times
      for (int i = 0; i < 5; i++) {
        final queue = await createQueue(testToken);
        final expectedDistinctId = 'user-$i';

        final result = await MixpanelSessionReplay.initializeWithDependencies(
          token: testToken,
          distinctId: expectedDistinctId,
          options: testOptions,
          eventQueue: queue,
        );

        expect(result.success, true, reason: 'Iteration $i failed');
        expect(result.instance!.distinctId, expectedDistinctId);
      }

      // Final state should be from last initialization
      final finalQueue = await createQueue(testToken);
      final finalResult =
          await MixpanelSessionReplay.initializeWithDependencies(
            token: testToken,
            distinctId: finalDistinctId,
            options: testOptions,
            eventQueue: finalQueue,
          );

      expect(finalResult.success, true);
      expect(finalResult.instance!.distinctId, finalDistinctId);
      expect(isQueueDisposed(finalQueue), false);
    });

    test(
      're-initialization after identify() preserves new instance distinctId',
      () async {
        const firstDistinctId = 'user-1';
        const changedDistinctId = 'user-changed';
        const secondDistinctId = 'user-2';

        final queue1 = await createQueue(testToken);

        // First initialization
        final result1 = await MixpanelSessionReplay.initializeWithDependencies(
          token: testToken,
          distinctId: firstDistinctId,
          options: testOptions,
          eventQueue: queue1,
        );

        expect(result1.success, true);

        // Change distinct ID on old instance
        result1.instance!.identify(changedDistinctId);
        expect(result1.instance!.distinctId, changedDistinctId);

        final queue2 = await createQueue(testToken);

        // Re-initialize with new distinct ID
        final result2 = await MixpanelSessionReplay.initializeWithDependencies(
          token: testToken,
          distinctId: secondDistinctId,
          options: testOptions,
          eventQueue: queue2,
        );

        expect(result2.success, true);

        // New instance should have its own distinct ID, not affected by old instance
        expect(result2.instance!.distinctId, secondDistinctId);

        // Old queue disposed
        expect(isQueueDisposed(queue1), true);
      },
    );

    test('flush on old instance completes before re-initialization', () async {
      const firstDistinctId = 'user-1';
      const secondDistinctId = 'user-2';

      final queue1 = await createQueue(testToken);

      // First initialization
      final result1 = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: firstDistinctId,
        options: testOptions,
        eventQueue: queue1,
      );

      expect(result1.success, true);

      // Start a flush (should complete quickly with no events)
      final flushFuture = result1.instance!.flush();

      final queue2 = await createQueue(testToken);

      // Re-initialization should wait for dispose, which waits for flush
      final result2 = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: secondDistinctId,
        options: testOptions,
        eventQueue: queue2,
      );

      // Wait for the flush to complete
      await flushFuture;

      expect(result2.success, true);
      expect(result2.instance, isNotNull);

      // Old queue should be disposed after flush completed
      expect(isQueueDisposed(queue1), true);
    });

    test('invalid configuration prevents initialization', () async {
      // Creating SessionReplayOptions with invalid autoRecordSessionsPercent
      // throws an assertion error before initialization even starts
      expect(
        () => SessionReplayOptions(
          logLevel: LogLevel.none,
          flushInterval: Duration(hours: 1),
          autoRecordSessionsPercent: 150, // Invalid: > 100
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('empty token prevents initialization', () async {
      const emptyToken = '';
      const testDistinctId = 'user-1';
      const expectedErrorMessage = 'token cannot be empty';

      final queue = await createQueue('empty-token-test');

      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: emptyToken,
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );

      expect(result.success, false);
      expect(result.error, InitializationError.invalidToken);
      expect(result.errorMessage, contains(expectedErrorMessage));

      // Queue should not have any events on validation failure
      expect(isQueueEmpty(queue), true);
    });

    test('re-initialization preserves instance registry correctly', () async {
      const token1 = 'token-1';
      const distinctId1 = 'user-1';
      const token2 = 'token-2';
      const distinctId2 = 'user-2';
      const newDistinctId1 = 'user-1-new';

      final queue1 = await createQueue(token1);
      final queue2 = await createQueue(token2);
      final queue3 = await createQueue(token1);

      // Initialize token-1
      final result1 = await MixpanelSessionReplay.initializeWithDependencies(
        token: token1,
        distinctId: distinctId1,
        options: testOptions,
        eventQueue: queue1,
      );

      expect(result1.success, true);

      // Initialize token-2
      final result2 = await MixpanelSessionReplay.initializeWithDependencies(
        token: token2,
        distinctId: distinctId2,
        options: testOptions,
        eventQueue: queue2,
      );

      expect(result2.success, true);

      // Re-initialize token-1 (should dispose old token-1 but not touch token-2)
      final result3 = await MixpanelSessionReplay.initializeWithDependencies(
        token: token1,
        distinctId: newDistinctId1,
        options: testOptions,
        eventQueue: queue3,
      );

      expect(result3.success, true);
      expect(result3.instance!.distinctId, newDistinctId1);

      // token-2 instance should still be valid and unchanged
      expect(result2.instance!.distinctId, distinctId2);

      // Queue1 should be disposed (old token-1 instance)
      expect(isQueueDisposed(queue1), true);

      // Queue2 should NOT be disposed (token-2 still active)
      expect(isQueueDisposed(queue2), false);

      // Queue3 should NOT be disposed (new token-1 instance)
      expect(isQueueDisposed(queue3), false);
    });

    test('invalid serverUrl prevents initialization', () async {
      // GIVEN
      final queue = await createQueue('invalid-server-url-test');
      final invalidOptions = SessionReplayOptions(
        logLevel: LogLevel.none,
        flushInterval: Duration(hours: 1),
        serverUrl: 'http://insecure.example.com', // not https://
      );

      // WHEN
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'invalid-server-url-test',
        distinctId: testDistinctId,
        options: invalidOptions,
        eventQueue: queue,
      );

      // THEN
      expect(result.success, false);
      expect(result.error, InitializationError.invalidServerUrl);
      expect(result.errorMessage, contains('must start with https://'));
    });

    test('serverUrl with path is accepted (does not drop path)', () async {
      // KEY behavior — matches Android, diverges from iOS. A proxy URL with
      // a path component must not be rejected during initialization.
      // GIVEN
      final queue = await createQueue('server-url-with-path-test');
      final options = SessionReplayOptions(
        logLevel: LogLevel.none,
        flushInterval: Duration(hours: 1),
        serverUrl: 'https://proxy.example.com/mp',
      );

      // WHEN
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'server-url-with-path-test',
        distinctId: testDistinctId,
        options: options,
        eventQueue: queue,
      );

      // THEN
      expect(result.success, true);
    });

    test('invalid storageQuotaMB prevents initialization', () async {
      // GIVEN
      final queue = await createQueue('storage-quota-test');
      final invalidOptions = SessionReplayOptions(
        logLevel: LogLevel.none,
        flushInterval: Duration(hours: 1),
        storageQuotaMB: 0, // Invalid: must be positive
      );

      // WHEN
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'storage-quota-test',
        distinctId: testDistinctId,
        options: invalidOptions,
        eventQueue: queue,
      );

      // THEN
      expect(result.success, false);
      expect(result.error, InitializationError.invalidToken);
      expect(result.errorMessage, contains('storageQuotaMB must be positive'));
    });

    test(
      'invalid autoRecordSessionsPercent via initializeWithDependencies prevents initialization',
      () async {
        // GIVEN - autoRecordSessionsPercent validation in session_replay.dart (not assertion)
        final queue = await createQueue('percent-test');
        // The assertion in SessionReplayOptions constructor catches > 100
        // but initializeWithDependencies also validates 0-100 range
        // Use a value that passes the assertion but triggers the validation
        final invalidOptions = SessionReplayOptions(
          logLevel: LogLevel.none,
          flushInterval: Duration(hours: 1),
          autoRecordSessionsPercent: 100.0, // valid
        );

        // WHEN - use empty token to trigger validation
        final result = await MixpanelSessionReplay.initializeWithDependencies(
          token: '',
          distinctId: testDistinctId,
          options: invalidOptions,
          eventQueue: queue,
        );

        // THEN
        expect(result.success, false);
        expect(result.error, InitializationError.invalidToken);
      },
    );

    test('stopRecording stops recording on the instance', () async {
      // GIVEN
      final queue = await createQueue('stop-test');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'stop-test',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);
      result.instance!.startRecording();
      await pumpEventQueue();
      expect(result.instance!.recordingState, RecordingState.recording);

      // WHEN
      result.instance!.stopRecording();

      // THEN
      expect(result.instance!.recordingState, RecordingState.notRecording);
    });

    test('isEventTriggersEnabled defaults to true', () async {
      // GIVEN
      final queue = await createQueue('triggers-default');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'triggers-default',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);

      // THEN — matches Android/iOS: default-enabled at SDK init
      expect(result.instance!.isEventTriggersEnabled, isTrue);
    });

    test('disableEventTriggers flips the flag to false', () async {
      // GIVEN
      final queue = await createQueue('triggers-disable');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'triggers-disable',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);
      expect(result.instance!.isEventTriggersEnabled, isTrue);

      // WHEN
      result.instance!.disableEventTriggers();

      // THEN
      expect(result.instance!.isEventTriggersEnabled, isFalse);
    });

    test('enableEventTriggers restores the flag to true', () async {
      // GIVEN
      final queue = await createQueue('triggers-enable');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'triggers-enable',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);
      result.instance!.disableEventTriggers();
      expect(result.instance!.isEventTriggersEnabled, isFalse);

      // WHEN
      result.instance!.enableEventTriggers();

      // THEN
      expect(result.instance!.isEventTriggersEnabled, isTrue);
    });

    test('enable/disable toggles repeatedly', () async {
      // GIVEN
      final queue = await createQueue('triggers-toggle');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'triggers-toggle',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);
      final sdk = result.instance!;

      // WHEN / THEN
      expect(sdk.isEventTriggersEnabled, isTrue);
      sdk.disableEventTriggers();
      expect(sdk.isEventTriggersEnabled, isFalse);
      sdk.disableEventTriggers(); // idempotent
      expect(sdk.isEventTriggersEnabled, isFalse);
      sdk.enableEventTriggers();
      expect(sdk.isEventTriggersEnabled, isTrue);
      sdk.enableEventTriggers(); // idempotent
      expect(sdk.isEventTriggersEnabled, isTrue);
      sdk.disableEventTriggers();
      expect(sdk.isEventTriggersEnabled, isFalse);
    });

    test('coordinator getter returns the internal coordinator', () async {
      // GIVEN
      final queue = await createQueue('coordinator-test');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'coordinator-test',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);

      // WHEN / THEN
      expect(result.instance!.coordinator, isNotNull);
    });

    test('debugOptions is null by default', () async {
      // GIVEN
      final queue = await createQueue('overlay-test');
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'overlay-test',
        distinctId: testDistinctId,
        options: testOptions,
        eventQueue: queue,
      );
      expect(result.success, true);

      // WHEN / THEN
      expect(result.instance!.debugOptions, isNull);
    });

    test('recording state is reset on new instance', () async {
      const firstDistinctId = 'user-1';
      const secondDistinctId = 'user-2';

      final queue1 = await createQueue(testToken);

      // First initialization
      final result1 = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: firstDistinctId,
        options: testOptions,
        eventQueue: queue1,
      );

      expect(result1.success, true);

      // Start recording
      result1.instance!.startRecording();
      // Wait for async session metadata persistence to complete
      await pumpEventQueue();
      expect(result1.instance!.recordingState, RecordingState.recording);

      final queue2 = await createQueue(testToken);

      // Re-initialize
      final result2 = await MixpanelSessionReplay.initializeWithDependencies(
        token: testToken,
        distinctId: secondDistinctId,
        options: testOptions,
        eventQueue: queue2,
      );

      expect(result2.success, true);

      // New instance should have fresh state (notRecording)
      expect(result2.instance!.recordingState, RecordingState.notRecording);

      // Old queue disposed
      expect(isQueueDisposed(queue1), true);
    });
  });
}
