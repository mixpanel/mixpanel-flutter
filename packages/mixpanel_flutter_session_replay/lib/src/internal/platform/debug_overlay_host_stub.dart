import 'debug_overlay_host.dart';

/// Non-web platforms capture the `RepaintBoundary` subtree rather than a
/// shared surface, so the in-tree overlay widget is already excluded.
DebugOverlayHost? createDebugOverlayHost() => null;
