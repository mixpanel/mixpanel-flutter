import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'wireframe.dart';
import 'wireframes_options.dart' show MaskDecision;

/// Event type enum
enum EventType {
  /// Session metadata (dimensions, device info)
  metadata,

  /// Captured screenshot with masking
  screenshot,

  /// User tap/click interaction
  interaction,

  /// Wireframe frame (structured list of visible UI elements)
  wireframe,
}

/// Sealed base class for event payload (type-safe union)
sealed class EventPayload {
  /// Serialize payload to JSON
  Map<String, dynamic> toJson();
}

/// Payload for metadata events (session dimensions, device info)
class MetadataPayload extends EventPayload {
  /// Screen width in logical pixels
  final int width;

  /// Screen height in logical pixels
  final int height;

  MetadataPayload({required this.width, required this.height});

  @override
  Map<String, dynamic> toJson() => {'width': width, 'height': height};
}

/// Payload for screenshot events
class ScreenshotPayload extends EventPayload {
  /// JPEG/PNG compressed image bytes
  final Uint8List imageData;

  ScreenshotPayload({required this.imageData});

  @override
  Map<String, dynamic> toJson() => {'screenshot_data': base64Encode(imageData)};
}

/// Payload for wireframe events.
///
/// Carries a viewport size and an ordered list of visible UI elements
/// (role/text/bounds/maskDecision). Serialized into a metadata JSON blob;
/// no binary column.
class WireframePayload extends EventPayload {
  WireframePayload({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.elements,
  });

  /// Viewport width in logical pixels.
  final int viewportWidth;

  /// Viewport height in logical pixels.
  final int viewportHeight;

  /// Elements in traversal order.
  final List<WireframeElement> elements;

  @override
  Map<String, dynamic> toJson() => {
    'viewport': [viewportWidth, viewportHeight],
    'elements': elements
        .map(
          (e) => {
            'role': e.role.wireName,
            'text': e.text,
            'bounds': [
              e.bounds.left.round(),
              e.bounds.top.round(),
              e.bounds.width.round(),
              e.bounds.height.round(),
            ],
            'maskDecision': e.maskDecision.index,
          },
        )
        .toList(),
  };
}

/// Payload for interaction events
class InteractionPayload extends EventPayload {
  /// RRWeb interaction type (e.g., touchStart, touchEnd, click)
  final int interactionType;

  /// Screen x coordinate
  final double x;

  /// Screen y coordinate
  final double y;

  InteractionPayload({
    required this.interactionType,
    required this.x,
    required this.y,
  });

  @override
  Map<String, dynamic> toJson() => {'type': interactionType, 'x': x, 'y': y};
}

/// Individual captured event within a session replay
class SessionReplayEvent {
  /// Parent session ID
  final String sessionId;

  /// User distinct ID at time of event capture
  final String distinctId;

  /// Event capture time (UTC)
  final DateTime timestamp;

  /// Event type
  final EventType type;

  /// Type-specific data
  final EventPayload payload;

  SessionReplayEvent({
    required this.sessionId,
    required this.distinctId,
    required this.timestamp,
    required this.type,
    required this.payload,
  });

  /// Serialize to SQLite row for insertion
  Map<String, dynamic> toDbRow() {
    final serialized = _serializePayload(payload);
    final dataSize =
        (serialized['metadata']?.length ?? 0) +
        (serialized['binary']?.length ?? 0);

    return {
      'session_id': sessionId,
      'distinct_id': distinctId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': type.index,
      'payload_metadata': serialized['metadata'],
      'payload_binary': serialized['binary'],
      'data_size': dataSize,
    };
  }

  /// Serialize payload to JSON metadata + optional binary
  static Map<String, dynamic> _serializePayload(EventPayload payload) {
    if (payload is MetadataPayload) {
      return {
        'metadata': jsonEncode({
          'width': payload.width,
          'height': payload.height,
          'version': 1,
        }),
        'binary': null,
      };
    } else if (payload is ScreenshotPayload) {
      return {
        'metadata': jsonEncode({'version': 1}),
        'binary': payload.imageData,
      };
    } else if (payload is InteractionPayload) {
      return {
        'metadata': jsonEncode({
          'type': payload.interactionType,
          'x': payload.x,
          'y': payload.y,
          'version': 1,
        }),
        'binary': null,
      };
    } else if (payload is WireframePayload) {
      return {
        'metadata': jsonEncode({
          'viewport': [payload.viewportWidth, payload.viewportHeight],
          'elements': payload.elements
              .map(
                (e) => {
                  'role': e.role.index,
                  'text': e.text,
                  'bounds': [
                    e.bounds.left,
                    e.bounds.top,
                    e.bounds.width,
                    e.bounds.height,
                  ],
                  'maskDecision': e.maskDecision.index,
                },
              )
              .toList(),
          'version': 1,
        }),
        'binary': null,
      };
    }

    throw UnsupportedError('Unknown payload type: ${payload.runtimeType}');
  }

  /// Deserialize payload from JSON metadata + optional binary
  static EventPayload _deserializePayload(
    EventType type,
    String? metadata,
    Uint8List? binary,
  ) {
    final json = metadata != null
        ? jsonDecode(metadata) as Map<String, dynamic>
        : <String, dynamic>{};

    if (type == EventType.metadata) {
      return MetadataPayload(
        width: json['width'] as int,
        height: json['height'] as int,
      );
    } else if (type == EventType.screenshot) {
      return ScreenshotPayload(imageData: binary!);
    } else if (type == EventType.wireframe) {
      final viewport = (json['viewport'] as List).cast<num>();
      final elements = (json['elements'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) {
            final bounds = (e['bounds'] as List).cast<num>();
            return WireframeElement(
              role: WireframeRole.values[e['role'] as int],
              text: e['text'] as String?,
              bounds: Rect.fromLTWH(
                bounds[0].toDouble(),
                bounds[1].toDouble(),
                bounds[2].toDouble(),
                bounds[3].toDouble(),
              ),
              maskDecision: MaskDecision.values[e['maskDecision'] as int],
            );
          })
          .toList(growable: false);
      return WireframePayload(
        viewportWidth: viewport[0].toInt(),
        viewportHeight: viewport[1].toInt(),
        elements: elements,
      );
    } else {
      // Interaction
      return InteractionPayload(
        interactionType: json['type'] as int,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );
    }
  }

  @override
  String toString() {
    return 'SessionReplayEvent(session: $sessionId, type: $type, timestamp: $timestamp)';
  }
}

/// Persisted event with database ID (returned from queries)
class PersistedSessionReplayEvent extends SessionReplayEvent {
  /// Database row ID (for deletion)
  final int id;

  /// Data size in bytes (from database for batching by size)
  final int dataSize;

  PersistedSessionReplayEvent({
    required this.id,
    required this.dataSize,
    required super.sessionId,
    required super.distinctId,
    required super.timestamp,
    required super.type,
    required super.payload,
  });

  /// Deserialize from SQLite row
  factory PersistedSessionReplayEvent.fromDbRow(Map<String, dynamic> row) {
    final type = EventType.values[row['type'] as int];
    final payload = SessionReplayEvent._deserializePayload(
      type,
      row['payload_metadata'] as String?,
      row['payload_binary'] as Uint8List?,
    );

    return PersistedSessionReplayEvent(
      id: row['id'] as int,
      dataSize: row['data_size'] as int,
      sessionId: row['session_id'] as String,
      distinctId: row['distinct_id'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        row['timestamp'] as int,
        isUtc: true,
      ),
      type: type,
      payload: payload,
    );
  }

  @override
  String toString() {
    return 'PersistedSessionReplayEvent(id: $id, session: $sessionId, type: $type, timestamp: $timestamp)';
  }
}
