import 'dart:typed_data';

import 'masking_directive.dart';

/// Recording state machine for session replay
///
/// Represents the current state of session replay recording.
/// Use this to understand what the SDK is doing and react accordingly.
///
/// State transitions:
/// ```
/// notRecording ──[sampling passes]──► initializing ──[DB done]──► recording
///      ▲                                                              │
///      └──────────────────[stopRecording/background]──────────────────┘
///
/// notRecording ──[sampling fails]──► notRecording (allows re-roll)
/// ```
enum RecordingState {
  /// Not currently recording
  ///
  /// This is both the initial state and the state after stopping.
  /// Calling `startRecording()` will evaluate sampling and potentially begin recording.
  notRecording,

  /// Sampling passed, session is being set up
  ///
  /// The SDK is persisting session metadata to the database.
  /// Recording will begin shortly once this completes.
  initializing,

  /// Actively recording session replay data
  ///
  /// Screenshots and interactions are being captured and queued for upload.
  recording,
}

/// Initialization errors that can occur during SDK setup
enum InitializationError {
  /// Empty or malformed token
  invalidToken,

  /// Cannot initialize local storage
  storageFailure,

  /// Platform security requirements not met (e.g., macOS App Sandbox not enabled)
  platformSecurityNotMet,

  /// `serverUrl` was empty, not HTTPS, or otherwise malformed.
  invalidServerUrl,
}

/// Capture errors (fail-safe - no unmasked data sent)
enum CaptureError {
  /// Widget tree traversal error
  maskDetectionFailed,

  /// Canvas rendering error
  maskApplicationFailed,

  /// No RepaintBoundary available
  renderBoundaryNotFound,

  /// OOM during capture
  insufficientMemory,

  /// JPEG encoding error
  compressionFailed,
}

/// Result type for SDK initialization
class InitializationResult<T> {
  /// Whether initialization succeeded
  final bool success;

  /// SDK instance if initialization succeeded
  final T? instance;

  /// Error type if initialization failed
  final InitializationError? error;

  /// Human-readable error message
  final String? errorMessage;

  /// Create a successful initialization result
  InitializationResult.success(this.instance)
    : success = true,
      error = null,
      errorMessage = null;

  /// Create a failed initialization result
  InitializationResult.failure(this.error, this.errorMessage)
    : success = false,
      instance = null;

  @override
  String toString() {
    if (success) return 'InitializationResult.success';
    return 'InitializationResult.failure($error: $errorMessage)';
  }
}

/// Result type for screenshot capture operations
sealed class CaptureResult {
  const CaptureResult();
}

/// Successful capture result
final class CaptureSuccess extends CaptureResult {
  /// Captured screenshot data (JPEG bytes)
  final Uint8List data;

  /// Screenshot width in pixels
  final int width;

  /// Screenshot height in pixels
  final int height;

  /// Number of masked regions applied
  final int maskCount;

  /// Timestamp when the screenshot was captured (when toImage() was called)
  final DateTime timestamp;

  /// Mask regions that were detected (for debug overlay)
  final List<MaskRegionInfo> maskRegions;

  const CaptureSuccess({
    required this.data,
    required this.width,
    required this.height,
    required this.maskCount,
    required this.timestamp,
    this.maskRegions = const [],
  });

  @override
  String toString() {
    return 'CaptureSuccess(${data.length} bytes, ${width}x$height, $maskCount masks)';
  }
}

/// Failed capture result
final class CaptureFailure extends CaptureResult {
  /// Error type
  final CaptureError error;

  /// Human-readable error message
  final String errorMessage;

  const CaptureFailure(this.error, this.errorMessage);

  @override
  String toString() {
    return 'CaptureFailure($error: $errorMessage)';
  }
}

/// Result type for flush operations
///
/// Represents the completion of a flush operation. Currently provides no
/// detailed information about the outcome, as flush is a best-effort operation
/// that may partially succeed (some batches uploaded, others failed).
///
/// This class is intentionally kept simple to allow for future extension
/// with more detailed result types (success, failure, skipped) without
/// breaking existing code.
class FlushResult {
  const FlushResult();
}
