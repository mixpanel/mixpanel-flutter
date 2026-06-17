┌─────────────────────────────────────────────────────────────────────┐
│                           USER'S APP                                 │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ calls initialize()
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  MixpanelSessionReplay (Instance)                    │
│                        PUBLIC API LAYER                              │
├─────────────────────────────────────────────────────────────────────┤
│ Fields:                                                              │
│   - _coordinator: SessionReplayCoordinator                           │
│                                                                      │
│ Static Methods:                                                      │
│   + initialize(token, distinctId, options)                           │
│     └─> Validates config                                            │
│     └─> Creates EventStorage, EventQueue (async)                    │
│     └─> Creates ALL internal components                             │
│     └─> Creates SessionReplayCoordinator                            │
│     └─> Creates & returns MixpanelSessionReplay instance            │
│                                                                      │
│ Public Methods (all delegate to coordinator):                       │
│   + startRecording() → _coordinator.startRecording()                │
│   + stopRecording() → _coordinator.stopRecording()                  │
│   + flush() → _coordinator.flush()                                  │
│   + dispose() → _coordinator.dispose()                              │
│   + get recordingState → _coordinator.recordingState                │
│   + get coordinator → _coordinator (internal use only)              │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   │ widget extracts coordinator
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│              MixpanelSessionReplayWidget (Widget)                    │
│                         WIDGET LAYER                                 │
├─────────────────────────────────────────────────────────────────────┤
│ Receives: MixpanelSessionReplay? instance                           │
│ Extracts: coordinator = instance?.coordinator                        │
│                                                                      │
│ Widget Tree:                                                         │
│   LifecycleObserver(coordinator)                                     │
│     └─> InteractionDetector(coordinator)                            │
│           └─> FrameMonitor(coordinator)                             │
│                 └─> RepaintBoundary                                 │
│                       └─> MaskOverlay (if debug enabled)            │
│                             └─> User's App                          │
└─────────────────────────────────────────────────────────────────────┘
    │             │                              │
    │             │                              │
    ▼             ▼                              ▼
┌─────────────┐ ┌──────────────────┐  ┌─────────────────────────┐
│Lifecycle    │ │Interaction       │  │   FrameMonitor          │
│Observer     │ │Detector          │  ├─────────────────────────┤
├─────────────┤ ├──────────────────┤  │ - Owns RepaintBoundary  │
│ - Monitors  │ │ - Listens for    │  │ - Owns CaptureScheduler │
│   app state │ │   touch events   │  │ - Monitors frames       │
│ - Calls:    │ │ - Calls:         │  │ - Calls:                │
│   onApp     │ │   record         │  │   captureSnapshot()     │
│   Foregrounded│ │   Interaction()│  │ - Manages mask overlay  │
│   onApp     │ └──────────────────┘  └─────────────────────────┘
│   Backgrounded│         │                       │
└─────────────┘           │                       │
    │                     └───────────┬───────────┘
    │                                 │
    │                 all delegate to │
    └─────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│              SessionReplayCoordinator (Coordinator)                  │
│                    INTERNAL IMPLEMENTATION LAYER                     │
├─────────────────────────────────────────────────────────────────────┤
│ Fields:                                                              │
│   - _screenshotCapturer: ScreenshotCapturer                         │
│   - _eventRecorder: EventRecorder                                   │
│   - _uploadService: UploadService                                   │
│   - _settingsService: SettingsService                               │
│   - _sessionManager: SessionManager                                 │
│   - _recordingState: RecordingState                                 │
│                                                                      │
│ Widget-called Methods:                                              │
│   + captureSnapshot(boundary) → captures screenshot                 │
│     └─> _screenshotCapturer.captureJPEG(boundary, maskRegions)     │
│     └─> _eventRecorder.recordScreenshot(jpg, sessionId, seq)       │
│   + captureInteraction(type, position)                              │
│     └─> _eventRecorder.recordInteraction(type, position)           │
│   + onAppForegrounded() → starts recording (if sampling passes)     │
│   + onAppBackgrounded() → flushes events, stops session             │
│                                                                      │
│ Public API Methods (called by user):                                │
│   + startRecording(sessionsPercent) → evaluates sampling, starts    │
│   + stopRecording() → sets state to stopped                         │
│   + identify(distinctId) → updates user identity                    │
│   + flush() → _uploadService.flush()                                │
│   + get recordingState → current RecordingState                     │
│   + get distinctId → current user distinct ID                       │
└─────────────────────────────────────────────────────────────────────┘
    │        │            │           │            │
    │        │            │           │            │
    ▼        ▼            ▼           ▼            ▼
┌──────┐ ┌────────┐ ┌───────┐ ┌─────────┐ ┌───────────┐
│Screen│ │Event   │ │Upload │ │Settings │ │Session    │
│shot  │ │Recorder│ │Service│ │Service  │ │Manager    │
│Captu │ ├────────┤ ├───────┤ ├─────────┤ ├───────────┤
│rer   │ │-Records│ │-Batches│ │-Checks  │ │-Generates │
├──────┤ │ screen │ │ events │ │ remote  │ │ session   │
│-Uses │ │ shots  │ │-Uploads│ │ settings│ │ IDs       │
│ Mask │ │ and    │ │ to API │ │-Returns │ │-Tracks    │
│Detect│ │ inter  │ │-Auto   │ │ enabled/│ │ sequence  │
│or &  │ │ actions│ │ flush  │ │ disabled│ │ numbers   │
│Mask  │ │-Queues │ │ timer  │ └─────────┘ └───────────┘
│Paintr│ │ to     │ └───────┘
└──────┘ │ queue  │     │
         └────────┘     │
             │          │
             └──────────┘
                  │
                  ▼
          ┌──────────────┐
          │  EventQueue  │
          │ (SQLite)     │
          │ - Stores     │
          │   events     │
          │ - Quota      │
          │   enforcement│
          └──────────────┘

## Performance Characteristics

### Capture Rate Limiting

The SDK implements intelligent rate limiting to minimize performance impact:

**Screenshot Capture:**
- **Maximum Rate:** 2 captures per second (500ms minimum interval)
- **Debouncing:** Frame callbacks are debounced to prevent excessive captures
- **Concurrent Prevention:** Only one capture can be in-progress at a time
- **Smart Scheduling:** If content changes during a capture, a new capture is automatically scheduled after completion

**Why 500ms?**
- Matches Android and iOS implementation
- Prevents excessive CPU/memory usage during rapid UI changes

**Interaction Recording:**
- No rate limiting (all touches/clicks are recorded)
