import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// Supplies frame IDs and raster reports independently of widget-test pumps.
/// The native test runner can leave frameData at -1 or emit real raster reports;
/// neither models the asynchronous web engine this barrier synchronizes with.
class RasterTestBinding extends AutomatedTestWidgetsFlutterBinding {
  late final _rasterDispatcher = RasterTestDispatcher();

  @override
  RasterTestDispatcher get platformDispatcher => _rasterDispatcher;

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    platformDispatcher.frameNumber++;
    super.handleBeginFrame(rawTimeStamp);
  }
}

class RasterTestDispatcher extends TestPlatformDispatcher {
  RasterTestDispatcher()
    : super(platformDispatcher: ui.PlatformDispatcher.instance);

  int frameNumber = 1;

  @override
  ui.FrameData get frameData => _FrameData(frameNumber);

  // Keep real native raster reports out of tests. Tests explicitly deliver
  // engine reports through this callback, just as the web engine does.
  @override
  ui.TimingsCallback? onReportTimings;
}

class _FrameData implements ui.FrameData {
  const _FrameData(this.frameNumber);

  @override
  final int frameNumber;
}
