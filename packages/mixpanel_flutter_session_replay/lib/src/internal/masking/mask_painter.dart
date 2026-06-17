import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../models/masking_directive.dart';

/// Applies masking overlays to captured screenshots
class MaskPainter {
  /// Color to use for mask overlays
  final ui.Color maskColor;

  MaskPainter({this.maskColor = const ui.Color(0xFFCCCCCC)});

  /// Apply mask overlays to an image
  ///
  /// Returns the masked image, or throws on error
  Future<ui.Image> applyMasks(
    ui.Image originalImage,
    List<MaskRegionInfo> maskRegions,
  ) async {
    try {
      // Create a canvas to draw on with explicit size
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(
          0,
          0,
          originalImage.width.toDouble(),
          originalImage.height.toDouble(),
        ),
      );

      // Draw the original image first
      canvas.drawImage(originalImage, Offset.zero, Paint());

      // Draw solid overlays for each mask region
      final maskPaint = Paint()
        ..color = maskColor
        ..style = PaintingStyle.fill;

      for (final maskInfo in maskRegions) {
        // Skip unmask regions — they exist only for debug overlay visualization
        if (maskInfo.source == MaskSource.unmask) continue;
        canvas.drawRect(maskInfo.bounds, maskPaint);
      }

      // Convert to image
      final picture = recorder.endRecording();
      final maskedImage = await picture.toImage(
        originalImage.width,
        originalImage.height,
      );

      return maskedImage;
    } catch (e) {
      // Mask application failed - fail safe
      throw MaskApplicationException('Failed to apply masks: $e');
    }
  }
}

/// Exception thrown when mask application fails
class MaskApplicationException implements Exception {
  final String message;

  MaskApplicationException(this.message);

  @override
  String toString() => 'MaskApplicationException: $message';
}
