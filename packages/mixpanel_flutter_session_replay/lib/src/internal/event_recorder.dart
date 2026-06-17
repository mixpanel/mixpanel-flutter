import 'dart:typed_data';

import 'package:clock/clock.dart';
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
    // Reset metadata dimensions so the first screenshot of this session
    // always emits a metadata event with screen dimensions.
    _lastMetadataDimensions = null;

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
  Future<void> recordSnapshot({
    required Uint8List imageData,
    required int width,
    required int height,
    required DateTime timestamp,
  }) async {
    _logger.debug('Recording snapshot...');

    // Save to event queue
    await _saveSnapshotToQueue(
      imageData: imageData,
      width: width,
      height: height,
      timestamp: timestamp,
    );
  }

  /// Record an interaction event
  ///
  /// [interactionType] - The RRWeb interaction type (e.g., touchStart, touchEnd, click)
  /// [position] - The position where the interaction occurred
  Future<void> recordInteraction(int interactionType, Offset position) async {
    try {
      // Use logical pixel coordinates directly
      // These will match the coordinate system of the screenshots
      final x = position.dx;
      final y = position.dy;

      _logger.debug('Recording interaction type $interactionType at ($x, $y)');

      await _saveInteractionToQueue(interactionType, x, y);
    } catch (e) {
      _logger.error('Failed to record interaction: $e');
      // Don't crash the app if storage fails
    }
  }

  /// Record metadata event (screen dimensions)
  ///
  /// Should be called once at the start of a session with the first screenshot dimensions,
  /// or if dimensions change.
  /// Uses the capture [timestamp] so metadata and its accompanying screenshot
  /// share the same time reference, keeping ID order and timestamp order aligned.
  Future<void> recordMetadata(int width, int height, DateTime timestamp) async {
    try {
      _logger.debug('Recording metadata: ${width}x$height');

      final payload = MetadataPayload(width: width, height: height);

      await _saveEventToQueue(
        type: EventType.metadata,
        payload: payload,
        timestamp: timestamp,
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
  }) async {
    _logger.debug('Result dimensions: ${width}x$height');

    // Record metadata event if:
    // 1. This is the first screenshot (dimensions never set), OR
    // 2. The dimensions have changed (e.g., window was resized)
    final currentDimensions = Offset(width.toDouble(), height.toDouble());
    final dimensionsChanged = _lastMetadataDimensions != currentDimensions;

    if (dimensionsChanged) {
      await recordMetadata(width, height, timestamp);
      _lastMetadataDimensions = currentDimensions;
    }

    final payload = ScreenshotPayload(imageData: imageData);

    await _saveEventToQueue(
      type: EventType.screenshot,
      payload: payload,
      timestamp: timestamp,
    );
  }

  /// Save interaction to event queue
  Future<void> _saveInteractionToQueue(
    int interactionType,
    double x,
    double y,
  ) async {
    final payload = InteractionPayload(
      interactionType: interactionType,
      x: x,
      y: y,
    );

    await _saveEventToQueue(
      type: EventType.interaction,
      payload: payload,
      timestamp: clock.now(),
    );
  }

  /// Common method to save any event to the queue
  Future<void> _saveEventToQueue({
    required EventType type,
    required EventPayload payload,
    required DateTime timestamp,
  }) async {
    try {
      final session = sessionManager.getCurrentSession();

      _logger.debug(
        'Saving ${type.name} event to queue (session: ${session.id})',
      );

      final event = SessionReplayEvent(
        sessionId: session.id,
        distinctId: getDistinctId(),
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
