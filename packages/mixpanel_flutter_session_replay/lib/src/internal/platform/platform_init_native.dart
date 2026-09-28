export 'platform_init_types.dart';

import '../../models/masking_directive.dart';
import '../../models/configuration.dart';
import '../logger.dart';
import '../native_image_compressor.dart';
import '../screenshot_capturer.dart';
import '../storage/event_queue_interface.dart';
import '../storage/sqlite_event_queue.dart';
import '../wireframe/wireframe_emitter.dart';
import 'gzip_compressor.dart';
import 'platform_init_types.dart';

Future<PlatformInitResult> platformInit({
  required String token,
  required int storageQuotaMB,
  required MaskingDirective directive,
  required bool debugOverlayEnabled,
  required PlatformOptions platformOptions,
  WireframeEmitter? wireframeEmitter,
  required bool useAccessibilityLabelFallback,
  required MixpanelLogger logger,
  EventQueue? eventQueue,
}) async {
  final queue =
      eventQueue ??
      SqliteEventQueue(token: token, quotaMB: storageQuotaMB, logger: logger);
  await queue.initialize();
  await queue.removeAll();
  logger.debug('Cleared all existing data');

  final screenshotCapturer = ScreenshotCapturer(
    directive: directive,
    logger: logger,
    debugOverlayEnabled: debugOverlayEnabled,
    compressor: NativeImageCompressor(),
    wireframeEmitter: wireframeEmitter,
    useAccessibilityLabelFallback: useAccessibilityLabelFallback,
  );

  final mobile = platformOptions.mobile;
  return PlatformInitResult(
    queue: queue,
    screenshotCapturer: screenshotCapturer,
    gzipCompressor: createGzipCompressor(),
    wifiOnly: mobile.wifiOnly,
    backgroundBehavior: mobile.onBackground,
  );
}
