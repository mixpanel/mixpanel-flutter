/// rrweb event types
/// See: https://github.com/rrweb-io/rrweb/blob/master/packages/rrweb/src/types.ts
class RRWebEventType {
  static const int fullSnapshot = 2;
  static const int incrementalSnapshot = 3;
  static const int meta = 4;
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
}

/// rrweb mouse interaction types
class RRWebMouseInteraction {
  static const int touchStart = 7;
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
