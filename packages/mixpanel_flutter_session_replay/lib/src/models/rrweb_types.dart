/// rrweb event types
/// See: https://github.com/rrweb-io/rrweb/blob/master/packages/rrweb/src/types.ts
class RRWebEventType {
  static const int fullSnapshot = 2;
  static const int incrementalSnapshot = 3;
  static const int meta = 4;
  static const int custom = 5;
}

/// Tag names for rrweb Custom events (type 5) emitted by this SDK.
class RRWebCustomTags {
  /// Wireframe frame — structured list of visible UI elements piggybacked
  /// on the screenshot pass.
  static const String wireframe = 'mp_wireframe';
}

/// rrweb DOM node types
class RRWebNodeType {
  static const int document = 0;
  static const int documentType = 1;
  static const int element = 2;
  static const int text = 3;
}

/// rrweb incremental snapshot sources
class RRWebIncrementalSource {
  static const int mouseInteraction = 2;

  /// A batch of sampled drag positions between a down and a lift.
  static const int touchMove = 6;
}

/// rrweb mouse interaction types
class RRWebMouseInteraction {
  static const int touchStart = 7;
  static const int touchEnd = 9;
  static const int touchCancel = 10;
}

/// Budget for the sampled touch-move stream.
///
/// A gesture can produce a pointer move per frame (~120/s on a 120Hz display);
/// shipping all of them would swamp the queue without making the replay any
/// smoother. Values match the Android and iOS SDKs.
class TouchSampling {
  /// Minimum gap between two sampled pointer moves.
  static const Duration moveSampleInterval = Duration(milliseconds: 50);

  /// A batch is flushed once its samples span this much time.
  static const Duration moveBatchInterval = Duration(milliseconds: 500);

  /// Hard cap on a single batch, so a stuck gesture can't grow the queue
  /// without bound.
  static const int maxPositionsPerBatch = 100;
}

/// Node ID for the main screenshot image element
/// Matches Android SDK's PayloadObjectId.MAIN_SNAPSHOT
class RRWebNodeIds {
  static const int document = 1;
  static const int documentType = 2;
  static const int html = 3;
  static const int head = 4;
  static const int style = 17;
  static const int styleText = 18;
  static const int body = 25;
  static const int mainImage = 28;
  static const int imageContainer = 29;
}
