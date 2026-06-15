import 'dart:async';
import 'dart:ui' as ui;
import 'dart:isolate';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;

import '../models/configuration.dart';
import '../models/results.dart';
import '../models/masking_directive.dart';
import 'masking/mask_detector.dart';
import 'masking/mask_painter.dart';
import 'native_image_compressor.dart';
import 'logger.dart';

/// Compression strategy for captured screenshots.
///
/// Change [ScreenshotCapturer.compressionMode] to switch between strategies
/// for performance comparison.
enum CompressionMode {
  /// Native platform JPEG encoder via MethodChannel (default).
  /// Android: Bitmap.compress() (libjpeg-turbo), iOS: UIImage.jpegData()
  nativeJpeg,

  /// Pure Dart JPEG encoder via isolate (image package).
  dartJpeg,

  /// Pure Dart PNG encoder via isolate (lossless, deterministic for tests).
  dartPng,
}

/// Screenshot capturer with three-layer fail-safe masking
class ScreenshotCapturer {
  /// Masking directive for privacy rules (used as default)
  final MaskingDirective directive;

  /// Logger instance
  final MixpanelLogger _logger;

  /// Whether debug overlay is enabled (determines if we track unmask bounds)
  final bool _debugOverlayEnabled;

  /// Native image compressor for platform-accelerated JPEG encoding
  final NativeImageCompressor? _nativeCompressor;

  /// Compression strategy to use for production captures.
  /// Change this value to compare performance between strategies.
  CompressionMode compressionMode;

  /// Mask painter (reusable across captures)
  late final MaskPainter _maskPainter;

  ScreenshotCapturer({
    required this.directive,
    required MixpanelLogger logger,
    required bool debugOverlayEnabled,
    NativeImageCompressor? nativeCompressor,
    this.compressionMode = CompressionMode.nativeJpeg,
  }) : _logger = logger,
       _debugOverlayEnabled = debugOverlayEnabled,
       _nativeCompressor = nativeCompressor {
    _maskPainter = MaskPainter();
  }

  /// Capture screenshot with masking
  ///
  /// This method performs the core capture/mask/compress workflow.
  ///
  /// Parameters:
  /// - [boundary]: The render boundary to capture
  /// - [maskTypes]: Set of view types to auto-mask (overrides directive if provided)
  /// Returns CaptureResult with compressed image data or error
  Future<CaptureResult> capture(
    RenderRepaintBoundary boundary, {
    Set<AutoMaskedView>? maskTypes,
  }) async {
    final captureStart = clock.now();
    try {
      // Create mask detector with specified mask types or use default directive
      final maskDetector = MaskDetector(
        directive: maskTypes != null
            ? MaskingDirective(autoMaskTypes: maskTypes)
            : directive,
        trackUnmaskBounds: _debugOverlayEnabled,
      );

      // Using endOfFrame ensures both detectMaskRegions() and toImage() see the same painted state
      await SchedulerBinding.instance.endOfFrame;

      // Detect masks after paint is complete
      final maskDetectionStart = clock.now();
      MaskDetectionResult maskResult;
      try {
        maskResult = maskDetector.detectMaskRegions(boundary);
      } catch (e) {
        return CaptureFailure(
          CaptureError.maskDetectionFailed,
          'Failed to detect mask regions: $e',
        );
      }
      final maskRegions = maskResult.maskRegions;
      final maskDetectionTime = clock.now().difference(maskDetectionStart);
      _logger.debug(
        'Mask detection: ${maskDetectionTime.inMilliseconds}ms (found ${maskRegions.length} masks)',
      );

      // Skip capture when visual state would cause mask coordinate mismatch
      // (route transitions show overlapping unmasked content, overscroll stretch
      // shifts content via paint-only transform not reflected in getTransformTo)
      if (maskResult.shouldSkipCapture) {
        _logger.debug(
          'Skipping capture: visual state would cause mask mismatch',
        );
        return CaptureFailure(
          CaptureError.maskDetectionFailed,
          'Visual state would cause mask coordinate mismatch',
        );
      }

      // IMMEDIATELY capture image but don't await yet - this ensures both operations now see the same painted state
      // Because Dart is single-threaded, no other code can execute between mask detection
      // and toImage() call, ensuring they see identical frame state
      final captureTimestamp = clock.now();
      final imageFuture = boundary.toImage(pixelRatio: 1.0);

      // Wait for image rendering to complete
      ui.Image rawImage;
      try {
        rawImage = await imageFuture;
      } catch (e) {
        return CaptureFailure(
          CaptureError.renderBoundaryNotFound,
          'Failed to capture boundary: $e',
        );
      }
      final renderTime = clock.now().difference(captureTimestamp);
      _logger.debug(
        'Image rendering: ${renderTime.inMilliseconds}ms (${rawImage.width}x${rawImage.height})',
      );

      // Apply masks
      final maskPaintStart = clock.now();
      ui.Image maskedImage;
      try {
        maskedImage = await _maskPainter.applyMasks(rawImage, maskRegions);
      } catch (e) {
        rawImage.dispose();
        return CaptureFailure(
          CaptureError.maskApplicationFailed,
          'Failed to apply mask overlays: $e',
        );
      }
      final maskPaintTime = clock.now().difference(maskPaintStart);
      _logger.debug('Mask painting: ${maskPaintTime.inMilliseconds}ms');

      // Compress image
      final compressionStart = clock.now();
      Uint8List? compressedBytes;
      try {
        compressedBytes = await _compressImage(maskedImage);
      } catch (e) {
        rawImage.dispose();
        maskedImage.dispose();
        return CaptureFailure(
          CaptureError.compressionFailed,
          'Image compression failed: $e',
        );
      }
      final compressionTime = clock.now().difference(compressionStart);
      final formatName = compressionMode.name;
      _logger.debug(
        '$formatName compression: ${compressionTime.inMilliseconds}ms (${compressedBytes?.length ?? 0} bytes)',
      );

      // Store dimensions before cleanup
      final imageWidth = maskedImage.width;
      final imageHeight = maskedImage.height;
      final imageMaskCount = maskRegions.length;

      // Clean up
      rawImage.dispose();
      maskedImage.dispose();

      if (compressedBytes == null) {
        return CaptureFailure(
          CaptureError.insufficientMemory,
          'Failed to compress image (OOM)',
        );
      }

      final totalTime = clock.now().difference(captureStart);
      _logger.debug(
        'Total capture time: ${totalTime.inMilliseconds}ms (${imageWidth}x$imageHeight, ${(compressedBytes.length / 1024).toStringAsFixed(1)}KB)',
      );

      return CaptureSuccess(
        data: compressedBytes,
        width: imageWidth,
        height: imageHeight,
        maskCount: imageMaskCount,
        timestamp: captureTimestamp,
        maskRegions: maskRegions,
      );
    } catch (e) {
      final totalTime = clock.now().difference(captureStart);
      _logger.error('Capture failed after ${totalTime.inMilliseconds}ms: $e');
      return CaptureFailure(
        CaptureError.maskDetectionFailed,
        'Unexpected capture error: $e',
      );
    }
  }

  /// Compress image using the specified [CompressionMode].
  ///
  /// - Native mode (nativeJpeg): platform JPEG encoder via MethodChannel.
  ///   Compression runs on native background threads.
  /// - Dart modes (dartJpeg/dartPng): pure Dart encoder via background isolate.
  Future<Uint8List?> _compressImage(ui.Image image) async {
    try {
      // Get raw RGBA bytes
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;

      final rgbaBytes = byteData.buffer.asUint8List();

      // Platform-specific JPEG quality to match native SDKs:
      // iOS: 40 (ImageSettings.jpegCompressionRate = 0.4)
      // Android: 80 (Bitmap.compress quality = 80)
      final jpegQuality = defaultTargetPlatform == TargetPlatform.iOS ? 40 : 80;

      // Native compression (hardware-accelerated, runs on native background threads)
      if (_nativeCompressor != null &&
          compressionMode == CompressionMode.nativeJpeg) {
        return await _nativeCompressor.compressToJpeg(
          rgbaBytes,
          width: image.width,
          height: image.height,
          quality: jpegQuality,
        );
      }

      // Dart isolate compression (dartJpeg or png)
      final params = _CompressionParams(
        width: image.width,
        height: image.height,
        rgbaBytes: rgbaBytes,
        mode: compressionMode,
        jpegQuality: jpegQuality,
      );
      return await Isolate.run(() => _compressInBackground(params));
    } catch (e) {
      return null;
    }
  }

  /// Background isolate function for image compression
  static Uint8List? _compressInBackground(_CompressionParams params) {
    try {
      final imgImage = img.Image.fromBytes(
        width: params.width,
        height: params.height,
        bytes: params.rgbaBytes.buffer,
        order: img.ChannelOrder.rgba,
      );

      switch (params.mode) {
        case CompressionMode.dartJpeg:
        case CompressionMode.nativeJpeg:
          return Uint8List.fromList(
            img.encodeJpg(imgImage, quality: params.jpegQuality),
          );
        case CompressionMode.dartPng:
          return Uint8List.fromList(img.encodePng(imgImage));
      }
    } catch (e) {
      return null;
    }
  }

  /// Release native cached resources (bitmaps, buffers).
  Future<void> dispose() async {
    await _nativeCompressor?.dispose();
  }
}

/// Parameters for image compression in isolate
class _CompressionParams {
  final int width;
  final int height;
  final Uint8List rgbaBytes;
  final CompressionMode mode;
  final int jpegQuality;

  _CompressionParams({
    required this.width,
    required this.height,
    required this.rgbaBytes,
    required this.mode,
    required this.jpegQuality,
  });
}
