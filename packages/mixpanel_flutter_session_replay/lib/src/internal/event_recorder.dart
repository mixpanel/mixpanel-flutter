import 'dart:typed_data';

import 'package:flutter/rendering.dart';

import '../models/session.dart';
import '../models/session_event.dart';
import 'storage/event_queue_interface.dart';
import 'session/session_manager.dart';
import 'logger.dart';

/// Central event recorder for both screenshots and interactions
///
/// This class consolidates all event recording logic, managing the session state,
/// event queue, and distinct ID tracking in one place.
class EventRecorder {
  /// Event queue for storing all events
  final EventQueue eventQueue;

  /// Session manager for tracking active session
  final SessionManager sessionManager;

  /// Callback to get the current distinct ID
  final String Function() getDistinctId;

  /// Logger instance
  final MixpanelLogger _logger;

  /// Track last dimensions to detect size changes (and first screenshot)
  /// null value indicates metadata has never been sent
  /// Stores dimensions as Offset(width, height) for compact representation
  Offset? _lastMetadataDimensions;

  /// Session the cached dimensions were emitted under, so each session emits
  /// its own metadata even when the dimensions are unchanged
  String? _lastMetadataSessionId;

  EventRecorder({
    required this.eventQueue,
    required this.sessionManager,
    required this.getDistinctId,
    required MixpanelLogger logger,
  }) : _logger = logger;

  /// Record session start in storage
  ///
  /// Creates session metadata in the event queue to store the session start time.
  /// This is called when startRecording() is invoked to ensure we have the correct
  /// replay_start_time for old sessions.
  Future<void> recordSession(Session session) async {
    try {
      await eventQueue.createSessionMetadata(session);
      _logger.debug('Session metadata created for ${session.id}');
    } catch (e) {
      _logger.error('Failed to create session metadata: $e');
      // Don't crash the app if storage fails
    }
  }

  /// Record a screenshot event
  ///
  /// Saves the provided screenshot data as an event.
  /// [sessionId] and [distinctId] are the identity pinned at capture time.
  Future<void> recordSnapshot({
    required Uint8List imageData,
    required int width,
    required int height,
    required DateTime timestamp,
    required String sessionId,
    required String distinctId,
  }) async {
    _logger.debug('Recording snapshot...');

    // Save to event queue
    await _saveSnapshotToQueue(
      imageData: imageData,
      width: width,
      height: height,
      timestamp: timestamp,
      sessionId: sessionId,
      distinctId: distinctId,
    );
  }

  /// Record a gesture boundary — down, lift, or cancel.
  ///
  /// [interactionType] - The RRWeb interaction type (touchStart, touchEnd,
  /// touchCancel)
  /// [position] - The position where the interaction occurred
  /// [timestamp] - When the pointer event happened, not when it was queued.
  /// Touches are timestamped accurately at the source so they stay ordered
  /// against the screenshot stream, which sits behind compression.
  Future<void> recordInteraction(
    int interactionType,
    Offset position,
    DateTime timestamp,
  ) async {
    try {
      // Use logical pixel coordinates directly
      // These will match the coordinate system of the screenshots
      final x = position.dx;
      final y = position.dy;

      _logger.debug('Recording interaction type $interactionType at ($x, $y)');

      await _saveInteractionToQueue(interactionType, x, y, timestamp);
    } catch (e) {
      _logger.error('Failed to record interaction: $e');
      // Don't crash the app if storage fails
    }
  }

  /// Record a batch of sampled drag positions.
  ///
  /// [positions] must be ordered oldest to newest and non-empty; [timestamp]
  /// is that of the final position, which every `timeOffset` is relative to.
  Future<void> recordTouchMove({
    required List<TouchPosition> positions,
    required DateTime timestamp,
  }) async {
    if (positions.isEmpty) return;
    try {
      _logger.debug('Recording touch move (${positions.length} positions)');

      await _saveEventToQueue(
        type: EventType.touchMove,
        payload: TouchMovePayload(positions: positions),
        timestamp: timestamp,
      );
    } catch (e) {
      _logger.error('Failed to record touch move: $e');
      // Don't crash the app if storage fails
    }
  }

  /// Record a wireframe event.
  ///
  /// Callers pass the same [timestamp] used for the accompanying screenshot
  /// so the wireframe and screenshot align in the replay stream.
  Future<void> recordWireframe({
    required WireframePayload payload,
    required DateTime timestamp,
    required String sessionId,
    required String distinctId,
  }) async {
    _logger.debug('Recording wireframe (${payload.elements.length} elements)');
    try {
      await _saveEventToQueue(
        type: EventType.wireframe,
        payload: payload,
        timestamp: timestamp,
        sessionId: sessionId,
        distinctId: distinctId,
      );
    } catch (e) {
      _logger.error('Failed to record wireframe: $e');
    }
  }

  /// Record metadata event (screen dimensions)
  ///
  /// Should be called once at the start of a session with the first screenshot dimensions,
  /// or if dimensions change.
  /// Uses the capture [timestamp] so metadata and its accompanying screenshot
  /// share the same time reference, keeping ID order and timestamp order aligned.
  Future<void> recordMetadata(
    int width,
    int height,
    DateTime timestamp, {
    String? sessionId,
    String? distinctId,
  }) async {
    try {
      _logger.debug('Recording metadata: ${width}x$height');

      final payload = MetadataPayload(width: width, height: height);

      await _saveEventToQueue(
        type: EventType.metadata,
        payload: payload,
        timestamp: timestamp,
        sessionId: sessionId,
        distinctId: distinctId,
      );
    } catch (e) {
      _logger.error('Failed to record metadata: $e');
      // Don't crash the app if storage fails
    }
  }

  /// Save snapshot to event queue
  Future<void> _saveSnapshotToQueue({
    required Uint8List imageData,
    required int width,
    required int height,
    required DateTime timestamp,
    required String sessionId,
    required String distinctId,
  }) async {
    _logger.debug('Result dimensions: ${width}x$height');

    // Record metadata event if:
    // 1. This is the first screenshot of this session, OR
    // 2. The dimensions have changed (e.g., window was resized)
    final currentDimensions = Offset(width.toDouble(), height.toDouble());
    final needsMetadata =
        _lastMetadataSessionId != sessionId ||
        _lastMetadataDimensions != currentDimensions;

    if (needsMetadata) {
      await recordMetadata(
        width,
        height,
        timestamp,
        sessionId: sessionId,
        distinctId: distinctId,
      );
      _lastMetadataSessionId = sessionId;
      _lastMetadataDimensions = currentDimensions;
    }

    final payload = ScreenshotPayload(imageData: imageData);

    await _saveEventToQueue(
      type: EventType.screenshot,
      payload: payload,
      timestamp: timestamp,
      sessionId: sessionId,
      distinctId: distinctId,
    );
  }

  /// Save interaction to event queue
  Future<void> _saveInteractionToQueue(
    int interactionType,
    double x,
    double y,
    DateTime timestamp,
  ) async {
    final payload = InteractionPayload(
      interactionType: interactionType,
      x: x,
      y: y,
    );

    await _saveEventToQueue(
      type: EventType.interaction,
      payload: payload,
      timestamp: timestamp,
    );
  }

  /// Common method to save any event to the queue
  Future<void> _saveEventToQueue({
    required EventType type,
    required EventPayload payload,
    required DateTime timestamp,
    String? sessionId,
    String? distinctId,
  }) async {
    try {
      final eventSessionId = sessionId ?? sessionManager.getCurrentSession().id;

      _logger.debug(
        'Saving ${type.name} event to queue (session: $eventSessionId)',
      );

      final event = SessionReplayEvent(
        sessionId: eventSessionId,
        distinctId: distinctId ?? getDistinctId(),
        timestamp: timestamp,
        type: type,
        payload: payload,
      );

      await eventQueue.add(event);
      _logger.debug(
        '${type.name[0].toUpperCase()}${type.name.substring(1)} event saved to queue successfully',
      );
    } catch (e) {
      _logger.error('Failed to save ${type.name} event: $e');
      // Don't crash the app if storage fails
    }
  }

  /// Dispose resources
  ///
  /// Closes the database connection.
  Future<void> dispose() async {
    _logger.debug('EventRecorder disposing...');
    await eventQueue.dispose();
    _logger.debug('EventRecorder disposed');
  }
}
