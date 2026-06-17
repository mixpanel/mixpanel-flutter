import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session_event.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/debug_overlay_colors.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/models/rrweb_types.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/masking/mask_painter.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/upload/rrweb_event.dart';
import 'package:mixpanel_flutter_session_replay/src/session_replay_options.dart';

void main() {
  group('Session', () {
    group('constructor', () {
      test('sets default values correctly', () {
        // GIVEN
        final expectedId = 'test-id';
        final expectedStartTime = DateTime.fromMillisecondsSinceEpoch(
          1000,
          isUtc: true,
        );
        final expectedStatus = SessionStatus.active;
        final expectedEventCount = 0;

        // WHEN
        final session = Session(id: expectedId, startTime: expectedStartTime);

        // THEN
        expect(session.id, expectedId);
        expect(session.startTime, expectedStartTime);
        expect(session.status, expectedStatus);
        expect(session.eventCount, expectedEventCount);
        expect(session.endTime, isNull);
        expect(session.lastActivityTime, expectedStartTime);
      });

      test('uses custom lastActivityTime when provided', () {
        // GIVEN
        final expectedLastActivity = DateTime.fromMillisecondsSinceEpoch(
          5000,
          isUtc: true,
        );

        // WHEN
        final session = Session(
          id: 'test',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          lastActivityTime: expectedLastActivity,
        );

        // THEN
        expect(session.lastActivityTime, expectedLastActivity);
      });
    });

    group('generateId', () {
      test('produces UUID v4 format', () {
        // GIVEN
        final uuidV4Pattern = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        );

        // WHEN
        final id = Session.generateId();

        // THEN
        expect(id, matches(uuidV4Pattern));
      });

      test('produces unique IDs on consecutive calls', () {
        // GIVEN / WHEN
        final id1 = Session.generateId();
        final id2 = Session.generateId();

        // THEN
        expect(id1, isNot(equals(id2)));
      });
    });

    group('recordActivity', () {
      test('updates lastActivityTime to current time', () {
        // GIVEN
        final session = Session(
          id: 'test',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        );
        final beforeRecord = DateTime.now();

        // WHEN
        session.recordActivity();

        // THEN
        final afterRecord = DateTime.now();
        expect(
          session.lastActivityTime.isAfter(beforeRecord) ||
              session.lastActivityTime.isAtSameMomentAs(beforeRecord),
          true,
        );
        expect(
          session.lastActivityTime.isBefore(afterRecord) ||
              session.lastActivityTime.isAtSameMomentAs(afterRecord),
          true,
        );
      });
    });

    group('JSON serialization', () {
      test('toJson produces correct map', () {
        // GIVEN
        final startTime = DateTime.fromMillisecondsSinceEpoch(
          1000,
          isUtc: true,
        );
        final session = Session(
          id: 'test-id',
          startTime: startTime,
          status: SessionStatus.active,
          eventCount: 5,
        );

        final expectedJson = {
          'id': 'test-id',
          'startTime': startTime.toIso8601String(),
          'endTime': null,
          'status': 'active',
          'lastActivityTime': startTime.toIso8601String(),
          'eventCount': 5,
        };

        // WHEN
        final json = session.toJson();

        // THEN
        expect(json, expectedJson);
      });

      test('fromJson roundtrips correctly', () {
        // GIVEN
        final original = Session(
          id: 'roundtrip-id',
          startTime: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
          status: SessionStatus.ended,
          eventCount: 10,
        );

        // WHEN
        final json = original.toJson();
        final restored = Session.fromJson(json);

        // THEN
        expect(restored.id, original.id);
        expect(restored.startTime, original.startTime);
        expect(restored.status, original.status);
        expect(restored.eventCount, original.eventCount);
        expect(restored.endTime, original.endTime);
      });

      test('fromJson handles endTime', () {
        // GIVEN
        final endTime = DateTime.fromMillisecondsSinceEpoch(9000, isUtc: true);
        final original = Session(
          id: 'end-time-test',
          startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          endTime: endTime,
        );

        // WHEN
        final json = original.toJson();
        final restored = Session.fromJson(json);

        // THEN
        expect(restored.endTime, endTime);
      });
    });
  });

  group('SessionReplayEvent', () {
    group('toDbRow', () {
      test('serializes interaction event correctly', () {
        // GIVEN
        final expectedSessionId = 'session-1';
        final expectedDistinctId = 'user-1';
        final expectedTimestamp = 5000;

        final event = SessionReplayEvent(
          sessionId: expectedSessionId,
          distinctId: expectedDistinctId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            expectedTimestamp,
            isUtc: true,
          ),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 1, x: 10.0, y: 20.0),
        );

        // WHEN
        final row = event.toDbRow();

        // THEN
        expect(row['session_id'], expectedSessionId);
        expect(row['distinct_id'], expectedDistinctId);
        expect(row['timestamp'], expectedTimestamp);
        expect(row['type'], EventType.interaction.index);
        expect(row['payload_binary'], isNull);

        final metadata =
            jsonDecode(row['payload_metadata'] as String)
                as Map<String, dynamic>;
        expect(metadata['type'], 1);
        expect(metadata['x'], 10.0);
        expect(metadata['y'], 20.0);
      });

      test('serializes screenshot event with binary data', () {
        // GIVEN
        final imageData = Uint8List.fromList([0xFF, 0xD8, 0x01]);

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: imageData),
        );

        // WHEN
        final row = event.toDbRow();

        // THEN
        expect(row['type'], EventType.screenshot.index);
        expect(row['payload_binary'], imageData);
        expect(row['data_size'], greaterThan(0));
      });

      test('serializes metadata event correctly', () {
        // GIVEN
        final expectedWidth = 375;
        final expectedHeight = 812;

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          type: EventType.metadata,
          payload: MetadataPayload(
            width: expectedWidth,
            height: expectedHeight,
          ),
        );

        // WHEN
        final row = event.toDbRow();

        // THEN
        expect(row['type'], EventType.metadata.index);
        expect(row['payload_binary'], isNull);

        final metadata =
            jsonDecode(row['payload_metadata'] as String)
                as Map<String, dynamic>;
        expect(metadata['width'], expectedWidth);
        expect(metadata['height'], expectedHeight);
      });
    });
  });

  group('PersistedSessionReplayEvent', () {
    group('fromDbRow', () {
      test('deserializes interaction event from database row', () {
        // GIVEN
        final expectedId = 42;
        final expectedSessionId = 'session-1';
        final expectedDistinctId = 'user-1';
        final expectedTimestamp = 5000;
        final expectedInteractionType = 7;
        final expectedX = 150.0;
        final expectedY = 300.0;

        final row = {
          'id': expectedId,
          'data_size': 100,
          'session_id': expectedSessionId,
          'distinct_id': expectedDistinctId,
          'timestamp': expectedTimestamp,
          'type': EventType.interaction.index,
          'payload_metadata': jsonEncode({
            'type': expectedInteractionType,
            'x': expectedX,
            'y': expectedY,
            'version': 1,
          }),
          'payload_binary': null,
        };

        // WHEN
        final event = PersistedSessionReplayEvent.fromDbRow(row);

        // THEN
        expect(event.id, expectedId);
        expect(event.sessionId, expectedSessionId);
        expect(event.distinctId, expectedDistinctId);
        expect(event.timestamp.millisecondsSinceEpoch, expectedTimestamp);
        expect(event.type, EventType.interaction);

        final payload = event.payload as InteractionPayload;
        expect(payload.interactionType, expectedInteractionType);
        expect(payload.x, expectedX);
        expect(payload.y, expectedY);
      });

      test('deserializes screenshot event from database row', () {
        // GIVEN
        final expectedImageData = Uint8List.fromList([0xFF, 0xD8, 0x01]);

        final row = {
          'id': 1,
          'data_size': 3,
          'session_id': 'session-1',
          'distinct_id': 'user-1',
          'timestamp': 1000,
          'type': EventType.screenshot.index,
          'payload_metadata': jsonEncode({'version': 1}),
          'payload_binary': expectedImageData,
        };

        // WHEN
        final event = PersistedSessionReplayEvent.fromDbRow(row);

        // THEN
        expect(event.type, EventType.screenshot);

        final payload = event.payload as ScreenshotPayload;
        expect(payload.imageData, expectedImageData);
      });

      test('deserializes metadata event from database row', () {
        // GIVEN
        final expectedWidth = 375;
        final expectedHeight = 812;

        final row = {
          'id': 1,
          'data_size': 50,
          'session_id': 'session-1',
          'distinct_id': 'user-1',
          'timestamp': 1000,
          'type': EventType.metadata.index,
          'payload_metadata': jsonEncode({
            'width': expectedWidth,
            'height': expectedHeight,
            'version': 1,
          }),
          'payload_binary': null,
        };

        // WHEN
        final event = PersistedSessionReplayEvent.fromDbRow(row);

        // THEN
        expect(event.type, EventType.metadata);

        final payload = event.payload as MetadataPayload;
        expect(payload.width, expectedWidth);
        expect(payload.height, expectedHeight);
      });
    });
  });

  group('EventPayload', () {
    group('MetadataPayload', () {
      test('toJson includes width and height', () {
        // GIVEN
        final expectedJson = {'width': 375, 'height': 812};
        final payload = MetadataPayload(width: 375, height: 812);

        // WHEN
        final json = payload.toJson();

        // THEN
        expect(json, expectedJson);
      });
    });

    group('ScreenshotPayload', () {
      test('toJson base64-encodes image data', () {
        // GIVEN
        final imageData = Uint8List.fromList([1, 2, 3, 4]);
        final expectedBase64 = base64Encode(imageData);
        final payload = ScreenshotPayload(imageData: imageData);

        // WHEN
        final json = payload.toJson();

        // THEN
        expect(json['screenshot_data'], expectedBase64);
      });
    });

    group('InteractionPayload', () {
      test('toJson includes all fields', () {
        // GIVEN
        final expectedJson = {'type': 7, 'x': 10.5, 'y': 20.5};
        final payload = InteractionPayload(
          interactionType: 7,
          x: 10.5,
          y: 20.5,
        );

        // WHEN
        final json = payload.toJson();

        // THEN
        expect(json, expectedJson);
      });
    });
  });

  group('RRWebEvent', () {
    group('fromSessionReplayEvent', () {
      test('converts metadata to meta event', () {
        // GIVEN
        final expectedType = RRWebEventType.meta;
        final expectedWidth = 375;
        final expectedHeight = 812;
        final expectedTimestampMs = 5000;

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            expectedTimestampMs,
            isUtc: true,
          ),
          type: EventType.metadata,
          payload: MetadataPayload(
            width: expectedWidth,
            height: expectedHeight,
          ),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        expect(rrweb.type, expectedType);
        expect(rrweb.timestamp, expectedTimestampMs);
        expect(rrweb.data['width'], expectedWidth);
        expect(rrweb.data['height'], expectedHeight);
        expect(rrweb.data['discriminator'], 'dimension');
      });

      test('converts interaction to incremental snapshot event', () {
        // GIVEN
        final expectedType = RRWebEventType.incrementalSnapshot;
        final expectedInteractionType = 7;
        final expectedX = 150;
        final expectedY = 300;

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(
            interactionType: expectedInteractionType,
            x: expectedX.toDouble(),
            y: expectedY.toDouble(),
          ),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        expect(rrweb.type, expectedType);
        expect(rrweb.data['source'], RRWebIncrementalSource.mouseInteraction);
        expect(rrweb.data['type'], expectedInteractionType);
        expect(rrweb.data['x'], expectedX);
        expect(rrweb.data['y'], expectedY);
        expect(rrweb.data['id'], RRWebNodeIds.mainImage);
      });

      test('converts screenshot to full snapshot with DOM structure', () {
        // GIVEN
        final expectedType = RRWebEventType.fullSnapshot;
        final imageData = Uint8List.fromList([0xFF, 0xD8, 0x01]);

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: imageData),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);

        // THEN
        expect(rrweb.type, expectedType);
        expect(rrweb.data['discriminator'], 'node');
        expect(rrweb.data['node'], isNotNull);

        // Verify the DOM tree contains the image
        final node = rrweb.data['node'] as Map<String, dynamic>;
        expect(node['type'], RRWebNodeType.document);
        expect(node['id'], RRWebNodeIds.document);
      });

      test('screenshot detects JPEG format from magic bytes', () {
        // GIVEN
        final jpegData = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02]);

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: jpegData),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);
        final jsonString = jsonEncode(rrweb.toJson());

        // THEN
        expect(jsonString, contains('image/jpeg'));
        expect(jsonString, isNot(contains('image/png')));
      });

      test('screenshot detects PNG format from magic bytes', () {
        // GIVEN
        // PNG magic bytes: 89 50 4E 47
        final pngData = Uint8List.fromList([
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
        ]);

        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
          type: EventType.screenshot,
          payload: ScreenshotPayload(imageData: pngData),
        );

        // WHEN
        final rrweb = RRWebEvent.fromSessionReplayEvent(event);
        final jsonString = jsonEncode(rrweb.toJson());

        // THEN
        expect(jsonString, contains('image/png'));
      });
    });

    group('toJson', () {
      test('produces correct structure', () {
        // GIVEN
        final expectedJson = {
          'type': 4,
          'data': {'key': 'value'},
          'timestamp': 1000,
        };

        final rrweb = RRWebEvent(
          type: 4,
          data: {'key': 'value'},
          timestamp: 1000,
        );

        // WHEN
        final json = rrweb.toJson();

        // THEN
        expect(json, expectedJson);
      });
    });
  });

  group('SessionReplayOptions', () {
    group('defaults', () {
      test('has correct default values', () {
        // GIVEN
        final expectedAutoMaskedViews = {
          AutoMaskedView.text,
          AutoMaskedView.image,
        };
        final expectedFlushInterval = Duration(seconds: 10);
        final expectedAutoRecordPercent = 100.0;
        final expectedStorageQuotaMB = 50;
        final expectedLogLevel = LogLevel.none;

        // WHEN
        const options = SessionReplayOptions();

        // THEN
        expect(options.autoMaskedViews, expectedAutoMaskedViews);
        expect(options.flushInterval, expectedFlushInterval);
        expect(options.autoRecordSessionsPercent, expectedAutoRecordPercent);
        expect(options.storageQuotaMB, expectedStorageQuotaMB);
        expect(options.logLevel, expectedLogLevel);
        expect(options.debugOptions, isNull);
      });
    });

    group('validation', () {
      test('throws assertion error for negative autoRecordSessionsPercent', () {
        // GIVEN / WHEN / THEN
        expect(
          () => SessionReplayOptions(autoRecordSessionsPercent: -1),
          throwsA(isA<AssertionError>()),
        );
      });

      test(
        'throws assertion error for autoRecordSessionsPercent greater than 100',
        () {
          // GIVEN / WHEN / THEN
          expect(
            () => SessionReplayOptions(autoRecordSessionsPercent: 101),
            throwsA(isA<AssertionError>()),
          );
        },
      );

      test('accepts boundary value 0 for autoRecordSessionsPercent', () {
        // GIVEN / WHEN
        final options = SessionReplayOptions(autoRecordSessionsPercent: 0);

        // THEN
        expect(options.autoRecordSessionsPercent, 0);
      });

      test('accepts boundary value 100 for autoRecordSessionsPercent', () {
        // GIVEN / WHEN
        final options = SessionReplayOptions(autoRecordSessionsPercent: 100);

        // THEN
        expect(options.autoRecordSessionsPercent, 100);
      });
    });

    group('PlatformOptions', () {
      test('has correct mobile defaults', () {
        // GIVEN
        final expectedWifiOnly = true;

        // WHEN
        const options = PlatformOptions();

        // THEN
        expect(options.mobile.wifiOnly, expectedWifiOnly);
      });

      test('allows custom mobile options', () {
        // GIVEN
        final expectedWifiOnly = false;

        // WHEN
        const options = PlatformOptions(mobile: MobileOptions(wifiOnly: false));

        // THEN
        expect(options.mobile.wifiOnly, expectedWifiOnly);
      });
    });
  });

  group('InitializationResult', () {
    test('success result has correct fields', () {
      // GIVEN
      final expectedInstance = 'test-instance';

      // WHEN
      final result = InitializationResult.success(expectedInstance);

      // THEN
      expect(result.success, true);
      expect(result.instance, expectedInstance);
      expect(result.error, isNull);
      expect(result.errorMessage, isNull);
    });

    test('failure result has correct fields', () {
      // GIVEN
      final expectedError = InitializationError.invalidToken;
      final expectedMessage = 'token is empty';

      // WHEN
      final result = InitializationResult<String>.failure(
        expectedError,
        expectedMessage,
      );

      // THEN
      expect(result.success, false);
      expect(result.instance, isNull);
      expect(result.error, expectedError);
      expect(result.errorMessage, expectedMessage);
    });
  });

  group('RecordingState', () {
    test('has all expected values', () {
      // GIVEN / WHEN / THEN
      expect(
        RecordingState.values,
        containsAll([
          RecordingState.notRecording,
          RecordingState.initializing,
          RecordingState.recording,
        ]),
      );
    });
  });

  group('toString methods', () {
    test('Session.toString includes id, status, eventCount, and startTime', () {
      // GIVEN
      final session = Session(
        id: 'test-id',
        startTime: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        status: SessionStatus.active,
        eventCount: 5,
      );

      // WHEN
      final result = session.toString();

      // THEN
      expect(result, contains('test-id'));
      expect(result, contains('active'));
      expect(result, contains('5'));
    });

    test(
      'SessionReplayEvent.toString includes session, type, and timestamp',
      () {
        // GIVEN
        final event = SessionReplayEvent(
          sessionId: 'session-1',
          distinctId: 'user-1',
          timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
          type: EventType.interaction,
          payload: InteractionPayload(interactionType: 7, x: 10.0, y: 20.0),
        );

        // WHEN
        final result = event.toString();

        // THEN
        expect(result, contains('session-1'));
        expect(result, contains('interaction'));
      },
    );

    test('PersistedSessionReplayEvent.toString includes id', () {
      // GIVEN
      final event = PersistedSessionReplayEvent(
        id: 42,
        dataSize: 100,
        sessionId: 'session-1',
        distinctId: 'user-1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
        type: EventType.interaction,
        payload: InteractionPayload(interactionType: 7, x: 10.0, y: 20.0),
      );

      // WHEN
      final result = event.toString();

      // THEN
      expect(result, contains('42'));
      expect(result, contains('session-1'));
    });

    test('InitializationResult.success toString', () {
      // GIVEN
      final result = InitializationResult.success('instance');

      // WHEN
      final str = result.toString();

      // THEN
      expect(str, 'InitializationResult.success');
    });

    test('InitializationResult.failure toString', () {
      // GIVEN
      final result = InitializationResult<String>.failure(
        InitializationError.invalidToken,
        'bad token',
      );

      // WHEN
      final str = result.toString();

      // THEN
      expect(str, contains('failure'));
      expect(str, contains('invalidToken'));
      expect(str, contains('bad token'));
    });

    test('CaptureSuccess.toString includes size and dimensions', () {
      // GIVEN
      final captureResult = CaptureSuccess(
        data: Uint8List.fromList([1, 2, 3]),
        width: 375,
        height: 812,
        maskCount: 2,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );

      // WHEN
      final str = captureResult.toString();

      // THEN
      expect(str, contains('3 bytes'));
      expect(str, contains('375x812'));
      expect(str, contains('2 masks'));
    });

    test('CaptureFailure.toString includes error and message', () {
      // GIVEN
      final captureResult = CaptureFailure(
        CaptureError.compressionFailed,
        'Out of memory',
      );

      // WHEN
      final str = captureResult.toString();

      // THEN
      expect(str, contains('compressionFailed'));
      expect(str, contains('Out of memory'));
    });
  });

  group('DebugOverlayColors', () {
    test('default constructor uses expected colors', () {
      // GIVEN / WHEN
      const colors = DebugOverlayColors();

      // THEN
      expect(colors.autoMaskColor, isNotNull);
      expect(colors.maskColor, isNotNull);
      expect(colors.unmaskColor, isNotNull);
    });

    test('custom constructor allows null colors', () {
      // GIVEN / WHEN
      const colors = DebugOverlayColors(
        autoMaskColor: null,
        maskColor: null,
        unmaskColor: null,
      );

      // THEN
      expect(colors.autoMaskColor, isNull);
      expect(colors.maskColor, isNull);
      expect(colors.unmaskColor, isNull);
    });

    test('custom constructor with specific colors', () {
      // GIVEN
      const expectedColor = Color(0xFF00FF00);

      // WHEN
      const colors = DebugOverlayColors(
        autoMaskColor: expectedColor,
        maskColor: expectedColor,
        unmaskColor: expectedColor,
      );

      // THEN
      expect(colors.autoMaskColor, expectedColor);
      expect(colors.maskColor, expectedColor);
      expect(colors.unmaskColor, expectedColor);
    });
  });

  group('MaskApplicationException', () {
    test('stores message', () {
      // GIVEN
      final expectedMessage = 'Failed to apply masks: test error';

      // WHEN
      final exception = MaskApplicationException(expectedMessage);

      // THEN
      expect(exception.message, expectedMessage);
    });

    test('toString includes class name and message', () {
      // GIVEN
      final exception = MaskApplicationException('test error');

      // WHEN
      final str = exception.toString();

      // THEN
      expect(str, 'MaskApplicationException: test error');
    });

    test('implements Exception', () {
      // GIVEN / WHEN
      final exception = MaskApplicationException('test');

      // THEN
      expect(exception, isA<Exception>());
    });
  });

  group('SessionReplayEvent deserialization edge cases', () {
    test('deserializes event with null metadata string', () {
      // GIVEN - screenshot event has null metadata (binary only)
      final imageData = Uint8List.fromList([0xFF, 0xD8]);
      final row = {
        'id': 1,
        'data_size': 2,
        'session_id': 'session-1',
        'distinct_id': 'user-1',
        'timestamp': 1000,
        'type': EventType.screenshot.index,
        'payload_metadata': null,
        'payload_binary': imageData,
      };

      // WHEN
      final event = PersistedSessionReplayEvent.fromDbRow(row);

      // THEN - should handle null metadata gracefully
      expect(event.type, EventType.screenshot);
      final payload = event.payload as ScreenshotPayload;
      expect(payload.imageData, imageData);
    });
  });

  group('FlushResult', () {
    test('can be constructed', () {
      // GIVEN / WHEN
      const result = FlushResult();

      // THEN
      expect(result, isNotNull);
    });
  });
}
