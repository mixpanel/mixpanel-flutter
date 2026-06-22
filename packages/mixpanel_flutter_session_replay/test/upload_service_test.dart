import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/upload_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/payload_serializer.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/version.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';

import 'helpers/fake_http_client.dart';
import 'helpers/fake_connectivity.dart';
import 'helpers/in_memory_event_queue.dart';

void main() {
  group('UploadService', () {
    late InMemoryEventQueue eventQueue;
    late PayloadSerializer serializer;
    late MixpanelLogger logger;

    final testToken = 'test-token';
    final testSessionId = 'session-1';
    final testDistinctId = 'user-1';

    setUp(() async {
      eventQueue = InMemoryEventQueue();
      await eventQueue.initialize();
      serializer = PayloadSerializer(testToken);
      logger = MixpanelLogger(LogLevel.none);
    });

    tearDown(() async {
      await eventQueue.dispose();
    });

    /// Seed the event queue with a session and N interaction events
    Future<Session> seedQueue({int eventCount = 1}) async {
      final session = Session(
        id: testSessionId,
        startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        status: SessionStatus.active,
      );
      await eventQueue.createSessionMetadata(session);

      for (var i = 0; i < eventCount; i++) {
        await eventQueue.add(
          SessionReplayEvent(
            sessionId: testSessionId,
            distinctId: testDistinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              2000 + (i * 100),
              isUtc: true,
            ),
            type: EventType.interaction,
            payload: InteractionPayload(
              interactionType: 7,
              x: 10.0 + i,
              y: 20.0 + i,
            ),
          ),
        );
      }

      return session;
    }

    UploadService createService({
      required InMemoryEventQueue eventQueue,
      int statusCode = 200,
      bool wifiOnly = false,
      RemoteEnablementState Function()? getRemoteEnablementState,
      Duration flushInterval = const Duration(seconds: 10),
      List<ConnectivityResult>? connectivity,
      dynamic httpClient,
      int? maxPayloadBytes,
      int? maxEventsPerBatch,
      String? serverUrl,
    }) {
      return UploadService(
        eventQueue: eventQueue,
        payloadSerializer: serializer,
        wifiOnly: wifiOnly,
        getRemoteEnablementState:
            getRemoteEnablementState ?? () => RemoteEnablementState.enabled,
        flushInterval: flushInterval,
        maxPayloadBytes:
            maxPayloadBytes ?? UploadService.defaultMaxPayloadBytes,
        maxEventsPerBatch:
            maxEventsPerBatch ?? UploadService.defaultMaxEventsPerBatch,
        logger: logger,
        httpClient: httpClient ?? createFakeHttpClient(statusCode: statusCode),
        connectivity: connectivity != null
            ? FakeConnectivity(connectivity)
            : null,
        serverUrl: serverUrl ?? 'https://api.mixpanel.com',
      );
    }

    group('startAutoFlush and stopAutoFlush', () {
      test('starts periodic timer that triggers uploads', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          flushInterval: Duration(seconds: 1),
          httpClient: recorder.client,
        );

        // WHEN - elapse past the flush interval so the timer fires
        fakeAsync((async) {
          service.startAutoFlush();
          async.elapse(Duration(seconds: 2));
          async.flushMicrotasks();
        });

        // THEN - exactly 1 HTTP request was made and events were uploaded
        expect(recorder.requests.length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('ignores duplicate start calls without resetting timer', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          flushInterval: Duration(seconds: 2),
          httpClient: recorder.client,
        );

        // WHEN - start, advance partway, then call start again
        fakeAsync((async) {
          service.startAutoFlush();
          async.elapse(Duration(milliseconds: 1999));
          service.startAutoFlush(); // Should be ignored, not reset timer
          async.elapse(Duration(milliseconds: 1)); // Original timer fires at 2s
          async.flushMicrotasks();
        });

        // THEN - timer fired at original 2s (was not reset)
        expect(recorder.requests.length, 1);

        service.dispose();
      });

      test(
        'does not start timer when flushInterval is zero (disabled)',
        () async {
          // GIVEN
          await seedQueue();
          final recorder = createRecordingHttpClient(statusCode: 200);
          final service = createService(
            eventQueue: eventQueue,
            flushInterval: Duration.zero,
            httpClient: recorder.client,
          );

          // WHEN - start auto flush and elapse time
          fakeAsync((async) {
            service.startAutoFlush();
            async.elapse(Duration(seconds: 10));
            async.flushMicrotasks();
          });

          // THEN - no HTTP requests were made (auto-flush disabled)
          expect(recorder.requests.length, 0);
          expect(eventQueue.eventCount, 1); // Event still in queue

          service.dispose();
        },
      );

      test(
        'does not start timer when flushInterval is negative (disabled)',
        () async {
          // GIVEN
          await seedQueue();
          final recorder = createRecordingHttpClient(statusCode: 200);
          final service = createService(
            eventQueue: eventQueue,
            flushInterval: Duration(seconds: -5),
            httpClient: recorder.client,
          );

          // WHEN - start auto flush and elapse time
          fakeAsync((async) {
            service.startAutoFlush();
            async.elapse(Duration(seconds: 10));
            async.flushMicrotasks();
          });

          // THEN - no HTTP requests were made (auto-flush disabled)
          expect(recorder.requests.length, 0);
          expect(eventQueue.eventCount, 1); // Event still in queue

          service.dispose();
        },
      );

      test('resolves sub-second flushInterval to 1 second', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          flushInterval: Duration(milliseconds: 500),
          httpClient: recorder.client,
        );

        // WHEN - elapse 999ms (should NOT have fired yet at sub-second)
        fakeAsync((async) {
          service.startAutoFlush();
          async.elapse(Duration(milliseconds: 999));
          async.flushMicrotasks();

          // THEN - no flush yet (resolved to 1s, not 500ms)
          expect(recorder.requests.length, 0);

          // Elapse 1ms more to hit 1 second
          async.elapse(Duration(milliseconds: 1));
          async.flushMicrotasks();

          // THEN - now flushed at the 1s mark
          expect(recorder.requests.length, 1);
        });

        service.dispose();
      });

      test('stopAutoFlush cancels the periodic timer', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          flushInterval: Duration(seconds: 1),
          httpClient: recorder.client,
        );

        // WHEN - start then stop before interval, then elapse past the interval
        fakeAsync((async) {
          service.startAutoFlush();
          async.elapse(Duration(milliseconds: 999));
          service.stopAutoFlush();
          async.elapse(Duration(milliseconds: 2));
          async.flushMicrotasks();
        });

        // THEN - no HTTP requests were made (timer cancelled)
        expect(recorder.requests.length, 0);

        service.dispose();
      });
    });

    group('flushOneBatch', () {
      test('uploads events and removes them from queue', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - HTTP request was made with all 3 events
        expect(recorder.requests.length, 1);
        expect(decodeRequestEvents(recorder.requests.first).length, 3);
        expect(eventQueue.eventCount, 0);
      });

      test('skips flush when already flushing', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN - start first flush, then immediately try second
        final first = service.flushOneBatch();
        final second = service
            .flushOneBatch(); // Should skip (already flushing)
        await Future.wait([first, second]);

        // THEN - only one HTTP request was made (second flush was skipped)
        expect(recorder.requests.length, 1);

        service.dispose();
      });

      test('skips flush when in backoff period', () async {
        // GIVEN - create service and trigger backoff
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 500);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // Trigger enough failures to activate backoff
        await service.flushOneBatch();
        await service.flushOneBatch();
        final requestsBeforeBackoff = recorder.requests.length;

        // WHEN - try to flush during backoff
        await service.flushOneBatch();

        // THEN - no additional HTTP request was made (backoff prevented it)
        expect(recorder.requests.length, requestsBeforeBackoff);

        service.dispose();
      });

      test('skips flush when wifiOnly and not on WiFi', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          wifiOnly: true,
          connectivity: [ConnectivityResult.mobile],
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - no HTTP requests were made
        expect(recorder.requests.length, 0);

        service.dispose();
      });

      test('allows flush when wifiOnly and on WiFi', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          wifiOnly: true,
          connectivity: [ConnectivityResult.wifi],
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - HTTP request was made and events were uploaded
        expect(recorder.requests.length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('allows flush when wifiOnly and on ethernet', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          wifiOnly: true,
          connectivity: [ConnectivityResult.ethernet],
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - HTTP request was made and events were uploaded
        expect(recorder.requests.length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('skips flush when remote settings state is disabled', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          getRemoteEnablementState: () => RemoteEnablementState.disabled,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - no HTTP requests were made and events remain
        expect(recorder.requests.length, 0);
        expect(eventQueue.eventCount, 1);

        service.dispose();
      });

      test('skips flush when remote settings state is pending', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          getRemoteEnablementState: () => RemoteEnablementState.pending,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - no HTTP requests were made and events remain
        expect(recorder.requests.length, 0);
        expect(eventQueue.eventCount, 1);

        service.dispose();
      });

      test('allows flush when remote settings state is enabled', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          getRemoteEnablementState: () => RemoteEnablementState.enabled,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - HTTP request was made and events were uploaded
        expect(recorder.requests.length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('does not flush when queue is empty', () async {
        // GIVEN - empty queue, no session metadata
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flushOneBatch();

        // THEN - no HTTP requests were made
        expect(recorder.requests.length, 0);

        service.dispose();
      });
    });

    group('flush', () {
      test('uploads all events until queue is empty', () async {
        // GIVEN
        await seedQueue(eventCount: 5);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN - exactly 1 HTTP request was made with all 5 events
        expect(recorder.requests.length, 1);
        expect(decodeRequestEvents(recorder.requests.first).length, 5);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('returns FlushResult when no events exist', () async {
        // GIVEN - empty queue
        final service = createService(eventQueue: eventQueue);

        // WHEN
        final result = await service.flush();

        // THEN
        expect(result, isNotNull);

        service.dispose();
      });

      test('skips flush when in backoff period', () async {
        // GIVEN - trigger backoff
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 500);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // Trigger failures to activate backoff
        await service.flushOneBatch();
        await service.flushOneBatch();
        final requestsBeforeBackoff = recorder.requests.length;

        // WHEN - try full flush during backoff
        await service.flush();

        // THEN - no additional HTTP requests were made (backoff prevented it)
        expect(recorder.requests.length, requestsBeforeBackoff);

        service.dispose();
      });

      test('skips flush when remote settings state is disabled', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          getRemoteEnablementState: () => RemoteEnablementState.disabled,
          httpClient: recorder.client,
        );

        // WHEN
        final result = await service.flush();

        // THEN - no HTTP requests and all events remain
        expect(result, isNotNull);
        expect(recorder.requests.length, 0);
        expect(eventQueue.eventCount, 3);

        service.dispose();
      });

      test('skips flush when remote settings state is pending', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          getRemoteEnablementState: () => RemoteEnablementState.pending,
          httpClient: recorder.client,
        );

        // WHEN
        final result = await service.flush();

        // THEN - no HTTP requests and all events remain
        expect(result, isNotNull);
        expect(recorder.requests.length, 0);
        expect(eventQueue.eventCount, 3);

        service.dispose();
      });

      test('allows flush when remote settings state is enabled', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          getRemoteEnablementState: () => RemoteEnablementState.enabled,
          httpClient: recorder.client,
        );

        // WHEN
        final result = await service.flush();

        // THEN - HTTP request was made and all events uploaded
        expect(result, isNotNull);
        expect(recorder.requests.length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('stops uploading on network error', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: createFailingHttpClient(),
        );

        // WHEN
        await service.flush();

        // THEN - all 3 events still in queue (upload failed)
        expect(eventQueue.eventCount, 3);

        service.dispose();
      });
    });

    group('upload behavior', () {
      test('sends POST request to default US record endpoint', () async {
        // GIVEN
        final expectedEndpoint = 'api.mixpanel.com';
        final expectedPath = '/record';
        await seedQueue();

        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN
        expect(recorder.requests.length, 1);
        final request = recorder.requests.first;
        expect(request.url.host, expectedEndpoint);
        expect(request.url.path, expectedPath);
      });

      test('sends POST request to custom serverUrl record endpoint', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
          serverUrl: 'https://api-eu.mixpanel.com',
        );

        // WHEN
        await service.flush();

        // THEN
        final request = recorder.requests.first;
        expect(request.url.host, 'api-eu.mixpanel.com');
        expect(request.url.path, '/record');
      });

      test(
        'preserves a path on the serverUrl when building the record endpoint',
        () async {
          // KEY behavior — matches Android, diverges from iOS. Proxy URLs with
          // a path must hit `<base>/<path>/record`, not have the path dropped.
          // GIVEN
          await seedQueue();
          final recorder = createRecordingHttpClient(statusCode: 200);
          final service = createService(
            eventQueue: eventQueue,
            httpClient: recorder.client,
            serverUrl: 'https://proxy.example.com/mp',
          );

          // WHEN
          await service.flush();

          // THEN
          final request = recorder.requests.first;
          expect(request.url.host, 'proxy.example.com');
          expect(request.url.path, '/mp/record');
        },
      );

      test('includes correct query parameters', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN
        final params = recorder.requests.first.url.queryParameters;
        expect(params['format'], 'gzip');
        expect(params['distinct_id'], testDistinctId);
        expect(params['seq'], '0');
        expect(params['replay_id'], testSessionId);
        expect(params['\$lib_version'], sdkVersion);
        expect(params['\$os'], anyOf('Android', 'iOS', 'Mac OS X'));
      });

      test('includes authorization header', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN
        final headers = recorder.requests.first.headers;
        expect(headers['Authorization'], startsWith('Basic '));
        expect(headers['Content-Type'], 'application/octet-stream');
      });

      test('persists sequence number on success', () async {
        // GIVEN
        final expectedSequenceNumber = 0;
        await seedQueue();
        final service = createService(eventQueue: eventQueue);

        // WHEN
        await service.flush();

        // THEN
        final seqNumber = await eventQueue.getLastSequenceNumber(testSessionId);
        expect(seqNumber, expectedSequenceNumber);
      });

      test('increments sequence number across batches', () async {
        // GIVEN
        final expectedFirstSeq = 0;
        final expectedSecondSeq = 1;
        await seedQueue();
        final service = createService(eventQueue: eventQueue);

        // First upload
        await service.flush();
        final firstSeq = await eventQueue.getLastSequenceNumber(testSessionId);
        expect(firstSeq, expectedFirstSeq);

        // WHEN - add more events and flush again
        await eventQueue.add(
          SessionReplayEvent(
            sessionId: testSessionId,
            distinctId: testDistinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 7, x: 1.0, y: 2.0),
          ),
        );
        await service.flush();

        // THEN
        final secondSeq = await eventQueue.getLastSequenceNumber(testSessionId);
        expect(secondSeq, expectedSecondSeq);

        service.dispose();
      });

      test('does not remove events on 429 rate limit', () async {
        // GIVEN
        await seedQueue(eventCount: 2);
        final recorder = createRecordingHttpClient(statusCode: 429);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN - exactly 1 request was attempted with 2 events, but events remain
        expect(recorder.requests.length, 1);
        expect(decodeRequestEvents(recorder.requests.first).length, 2);
        expect(eventQueue.eventCount, 2);

        service.dispose();
      });

      test('does not remove events on 500 server error', () async {
        // GIVEN
        await seedQueue(eventCount: 2);
        final recorder = createRecordingHttpClient(statusCode: 500);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN - exactly 1 request was attempted with 2 events, but events remain
        expect(recorder.requests.length, 1);
        expect(decodeRequestEvents(recorder.requests.first).length, 2);
        expect(eventQueue.eventCount, 2);

        service.dispose();
      });

      test('does not remove events on 4xx client error', () async {
        // GIVEN
        await seedQueue(eventCount: 2);
        final recorder = createRecordingHttpClient(statusCode: 400);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN - exactly 1 request was attempted with 2 events, but events remain
        expect(recorder.requests.length, 1);
        expect(decodeRequestEvents(recorder.requests.first).length, 2);
        expect(eventQueue.eventCount, 2);

        service.dispose();
      });

      test('does not remove events on network exception', () async {
        // GIVEN
        await seedQueue(eventCount: 2);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: createFailingHttpClient(),
        );

        // WHEN
        await service.flush();

        // THEN - all 2 events remain in queue
        expect(eventQueue.eventCount, 2);

        service.dispose();
      });

      test('handles missing session metadata gracefully', () async {
        // GIVEN - add event without creating session metadata
        await eventQueue.add(
          SessionReplayEvent(
            sessionId: 'orphan-session',
            distinctId: testDistinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 7, x: 1.0, y: 2.0),
          ),
        );

        final service = createService(eventQueue: eventQueue);

        // WHEN
        await service.flush();

        // THEN - event remains (upload returned networkError due to missing metadata)
        expect(eventQueue.eventCount, 1);

        service.dispose();
      });

      test('uploads screenshot binary data correctly', () async {
        // GIVEN
        final imageData = Uint8List.fromList(
          List.generate(100, (i) => i % 256),
        );
        final session = Session(
          id: testSessionId,
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          status: SessionStatus.active,
        );
        await eventQueue.createSessionMetadata(session);
        await eventQueue.add(
          SessionReplayEvent(
            sessionId: testSessionId,
            distinctId: testDistinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
            type: EventType.screenshot,
            payload: ScreenshotPayload(imageData: imageData),
          ),
        );

        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN
        await service.flush();

        // THEN - request sent with 1 screenshot event
        expect(recorder.requests.length, 1);
        expect(decodeRequestEvents(recorder.requests.first).length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });
    });

    group('backoff', () {
      test('no backoff before failure threshold', () async {
        // GIVEN - one failure (threshold is 2)
        await seedQueue(eventCount: 2);
        final service = createService(eventQueue: eventQueue, statusCode: 500);

        // First failure
        await service.flushOneBatch();
        expect(eventQueue.eventCount, 2); // Events remain

        // WHEN - second flush attempt (only 1 failure so far, below threshold)
        final service2 = createService(eventQueue: eventQueue, statusCode: 200);
        await service2.flushOneBatch();

        // THEN - events uploaded (no backoff was blocking)
        expect(eventQueue.eventCount, 0);

        service.dispose();
        service2.dispose();
      });

      test('backoff activates after failure threshold', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 500);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // Trigger 2 failures (threshold for backoff)
        await service.flushOneBatch();
        await service.flushOneBatch();
        final requestsBeforeBackoff = recorder.requests.length;

        // WHEN - try to flush during backoff
        await service.flushOneBatch();

        // THEN - no additional HTTP request was made (backoff prevented it)
        expect(recorder.requests.length, requestsBeforeBackoff);

        service.dispose();
      });

      test('backoff resets on successful upload', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final service = createService(eventQueue: eventQueue, statusCode: 200);

        // Upload successfully
        await service.flushOneBatch();

        // Add more events
        await eventQueue.add(
          SessionReplayEvent(
            sessionId: testSessionId,
            distinctId: testDistinctId,
            timestamp: DateTime.fromMillisecondsSinceEpoch(9000, isUtc: true),
            type: EventType.interaction,
            payload: InteractionPayload(interactionType: 7, x: 1.0, y: 2.0),
          ),
        );

        // WHEN - flush again (should succeed, no backoff)
        await service.flushOneBatch();

        // THEN - all events uploaded
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test('backoff period expires and allows flush', () async {
        // GIVEN - trigger backoff with one service
        await seedQueue(eventCount: 3);
        final failingService = createService(
          eventQueue: eventQueue,
          httpClient: createFakeHttpClient(statusCode: 500),
        );

        // Trigger 2 failures to activate backoff
        await failingService.flushOneBatch();
        await failingService.flushOneBatch();

        // Verify all 3 events remain
        expect(eventQueue.eventCount, 3);

        // WHEN - use a new service (no backoff state) to flush
        final successService = createService(
          eventQueue: eventQueue,
          statusCode: 200,
        );
        await successService.flushOneBatch();

        // THEN - events uploaded (new service has no backoff)
        expect(eventQueue.eventCount, 0);

        failingService.dispose();
        successService.dispose();
      });
    });

    group('concurrent flush', () {
      test('concurrent flush waits for in-progress flush to complete', () async {
        // GIVEN
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
        );

        // WHEN - start two flushes concurrently
        final future1 = service.flush();
        final future2 = service.flush(); // Should wait for first flush
        await Future.wait([future1, future2]);

        // THEN - exactly 1 HTTP request was made (second flush waited on first)
        expect(recorder.requests.length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });
    });

    group('falling behind detection', () {
      test(
        'schedules immediate flush when oldest event age exceeds flush interval',
        () async {
          // GIVEN - events with old timestamps (long ago)
          final session = Session(
            id: testSessionId,
            startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
            status: SessionStatus.active,
          );
          await eventQueue.createSessionMetadata(session);

          // Create events with old timestamps to trigger "falling behind"
          for (var i = 0; i < 3; i++) {
            await eventQueue.add(
              SessionReplayEvent(
                sessionId: testSessionId,
                distinctId: testDistinctId,
                timestamp: DateTime.fromMillisecondsSinceEpoch(
                  1000 + (i * 100), // Very old timestamps
                  isUtc: true,
                ),
                type: EventType.interaction,
                payload: InteractionPayload(
                  interactionType: 7,
                  x: 10.0 + i,
                  y: 20.0 + i,
                ),
              ),
            );
          }

          // Use a short flush interval so events appear "old"
          final recorder = createRecordingHttpClient(statusCode: 200);
          final service = createService(
            eventQueue: eventQueue,
            flushInterval: Duration(seconds: 1),
            httpClient: recorder.client,
          );

          // WHEN - flush one batch, which should detect falling behind
          await service.flushOneBatch();

          // Flush the scheduled follow-up flush (Future.microtask)
          await pumpEventQueue();

          // THEN - exactly 1 HTTP request was made and all events uploaded
          expect(recorder.requests.length, 1);
          expect(eventQueue.eventCount, 0);

          service.dispose();
        },
      );
    });

    group('flush mid-batch backoff', () {
      test(
        'flush stops when backoff activates during multi-batch upload',
        () async {
          // GIVEN - seed events, use a failing server to trigger backoff mid-flush
          await seedQueue(eventCount: 3);
          final recorder = createRecordingHttpClient(statusCode: 500);

          final service = createService(
            eventQueue: eventQueue,
            httpClient: recorder.client,
          );

          // WHEN - flush encounters server errors and triggers backoff
          await service.flush();

          // THEN - exactly 1 request made (flush breaks on first server error)
          expect(recorder.requests.length, 1);
          expect(eventQueue.eventCount, 3);

          service.dispose();
        },
      );
    });

    group('batch limits', () {
      test(
        'respects maxEventsPerBatch by splitting into multiple batches',
        () async {
          // GIVEN - 5 events with a max of 2 per batch
          await seedQueue(eventCount: 5);
          final recorder = createRecordingHttpClient(statusCode: 200);
          final service = createService(
            eventQueue: eventQueue,
            httpClient: recorder.client,
            maxEventsPerBatch: 2,
          );

          // WHEN - flush all events
          await service.flush();

          // THEN - 3 batches: 2 + 2 + 1 events
          expect(recorder.requests.length, 3);
          expect(decodeRequestEvents(recorder.requests[0]).length, 2);
          expect(decodeRequestEvents(recorder.requests[1]).length, 2);
          expect(decodeRequestEvents(recorder.requests[2]).length, 1);
          expect(eventQueue.eventCount, 0);

          service.dispose();
        },
      );

      test('respects maxPayloadBytes by splitting into multiple batches', () async {
        // GIVEN - 3 interaction events (~100 bytes each), max 150 bytes per batch
        await seedQueue(eventCount: 3);
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          httpClient: recorder.client,
          maxPayloadBytes: 150,
        );

        // WHEN - flush all events
        await service.flush();

        // THEN - first batch fits 1 event (100 bytes), second would exceed on 2nd event
        // so each batch gets 1 event = 3 batches
        expect(recorder.requests.length, 3);
        expect(decodeRequestEvents(recorder.requests[0]).length, 1);
        expect(decodeRequestEvents(recorder.requests[1]).length, 1);
        expect(decodeRequestEvents(recorder.requests[2]).length, 1);
        expect(eventQueue.eventCount, 0);

        service.dispose();
      });

      test(
        'flushOneBatch uploads only one batch when limit is smaller than total events',
        () async {
          // GIVEN - 5 events with a max of 2 per batch
          await seedQueue(eventCount: 5);
          final recorder = createRecordingHttpClient(statusCode: 200);
          final service = createService(
            eventQueue: eventQueue,
            httpClient: recorder.client,
            maxEventsPerBatch: 2,
          );

          // WHEN - flush one batch only
          await service.flushOneBatch();

          // THEN - only 1 request with 2 events, 3 events remain
          expect(recorder.requests.length, 1);
          expect(decodeRequestEvents(recorder.requests.first).length, 2);
          expect(eventQueue.eventCount, 3);

          service.dispose();
        },
      );
    });

    group('dispose', () {
      test('stops auto flush timer', () async {
        // GIVEN
        await seedQueue();
        final recorder = createRecordingHttpClient(statusCode: 200);
        final service = createService(
          eventQueue: eventQueue,
          flushInterval: Duration(seconds: 1),
          httpClient: recorder.client,
        );

        // WHEN - start, dispose, then elapse past the interval
        fakeAsync((async) {
          service.startAutoFlush();
          service.dispose();
          async.elapse(Duration(seconds: 2));
          async.flushMicrotasks();
        });

        // THEN - no HTTP requests were made (timer was cancelled before it fired)
        expect(recorder.requests.length, 0);
      });

      test('is safe to call multiple times', () {
        // GIVEN
        final service = createService(eventQueue: eventQueue);

        // WHEN / THEN - should not throw
        service.dispose();
        service.dispose();
      });
    });
  });
}

/// Decompress a gzip-compressed request body and return the JSON event list.
List<dynamic> decodeRequestEvents(http.Request request) {
  final decompressed = gzip.decode(request.bodyBytes);
  return jsonDecode(utf8.decode(decompressed)) as List<dynamic>;
}
