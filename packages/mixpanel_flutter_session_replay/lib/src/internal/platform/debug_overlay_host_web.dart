import 'dart:ui' show Color, Offset, Size;

import 'package:web/web.dart' as web;

import '../../models/debug_overlay_colors.dart';
import '../../models/masking_directive.dart';
import 'debug_overlay_host.dart';

DebugOverlayHost? createDebugOverlayHost() => _DomDebugOverlayHost();

/// Draws mask regions as DOM nodes layered over the Flutter canvas.
///
/// `createImageBitmap` reads the canvas backing store, so sibling DOM nodes
/// are never composited into a capture. The overlay can therefore stay visible
/// for the whole session instead of blinking off around every frame.
///
/// Deliberately built from `<div>` elements: `WebImageCompressor` collects
/// every `<canvas>` under a Flutter engine host and skips the frame when more
/// than one matches the viewport, so a debug canvas there would stop capture.
/// `<flt-platform-view>` is likewise avoided — it would trip the
/// platform-view policy and mask the entire frame.
class _DomDebugOverlayHost implements DebugOverlayHost {
  /// Same engine hosts `WebImageCompressor` searches for the capture surface.
  static const _viewHostSelector =
      'flutter-view, flt-glass-pane, flt-scene-host, flt-renderer';

  static const _containerId = 'mp-session-replay-debug-overlay';

  web.HTMLDivElement? _container;
  final List<web.HTMLDivElement> _regionNodes = <web.HTMLDivElement>[];
  bool _disposed = false;

  @override
  void update({
    required List<MaskRegionInfo> regions,
    required DebugOverlayColors colors,
    required Offset boundaryOrigin,
    required Size boundarySize,
  }) {
    if (_disposed) return;

    final painted = _paintOrder(regions, colors);
    if (painted.isEmpty && _container == null) return;

    final container = _container ??= _createContainer();
    final viewOrigin = _viewOrigin();
    container.style
      ..left = '${viewOrigin.dx + boundaryOrigin.dx}px'
      ..top = '${viewOrigin.dy + boundaryOrigin.dy}px'
      ..width = '${boundarySize.width}px'
      ..height = '${boundarySize.height}px'
      // One compositing group over opaque children, matching the widget
      // overlay: overlapping regions do not compound their transparency.
      ..opacity = '${colors.opacity}';

    while (_regionNodes.length < painted.length) {
      final node = web.HTMLDivElement()..style.position = 'absolute';
      container.append(node);
      _regionNodes.add(node);
    }
    while (_regionNodes.length > painted.length) {
      _regionNodes.removeLast().remove();
    }

    for (var index = 0; index < painted.length; index++) {
      final (region, color) = painted[index];
      final bounds = region.bounds;
      _regionNodes[index].style
        ..left = '${bounds.left}px'
        ..top = '${bounds.top}px'
        ..width = '${bounds.width}px'
        ..height = '${bounds.height}px'
        ..backgroundColor = _cssColor(color);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _regionNodes.clear();
    _container?.remove();
    _container = null;
  }

  web.HTMLDivElement _createContainer() {
    // A hot restart leaves the previous isolate's overlay behind.
    web.document.getElementById(_containerId)?.remove();

    final container = web.HTMLDivElement()..id = _containerId;
    container.style
      ..position = 'fixed'
      ..pointerEvents = 'none'
      ..overflow = 'hidden'
      ..zIndex = '2147483647';
    web.document.body?.append(container);
    return container;
  }

  /// Top-left of the Flutter view in viewport coordinates, which is the
  /// coordinate space a `position: fixed` container is placed in.
  static Offset _viewOrigin() {
    final host = web.document.querySelector(_viewHostSelector);
    if (host == null) return Offset.zero;
    final bounds = host.getBoundingClientRect();
    return Offset(bounds.left.toDouble(), bounds.top.toDouble());
  }

  /// Regions in the widget overlay's paint order, dropping the sources whose
  /// color is null because visualization is disabled for them.
  static List<(MaskRegionInfo, Color)> _paintOrder(
    List<MaskRegionInfo> regions,
    DebugOverlayColors colors,
  ) {
    final painted = <(MaskRegionInfo, Color)>[];
    void addAll(bool Function(MaskSource) matches, Color? color) {
      if (color == null) return;
      for (final region in regions) {
        if (matches(region.source)) painted.add((region, color));
      }
    }

    addAll((s) => s == MaskSource.unmask, colors.unmaskColor);
    addAll((s) => s == MaskSource.auto, colors.autoMaskColor);
    addAll(
      (s) => s == MaskSource.manual || s == MaskSource.security,
      colors.maskColor,
    );
    return painted;
  }

  static String _cssColor(Color color) {
    final argb = color.toARGB32();
    final alpha = ((argb >> 24) & 0xFF) / 255.0;
    final red = (argb >> 16) & 0xFF;
    final green = (argb >> 8) & 0xFF;
    final blue = argb & 0xFF;
    return 'rgba($red, $green, $blue, ${alpha.toStringAsFixed(3)})';
  }
}
