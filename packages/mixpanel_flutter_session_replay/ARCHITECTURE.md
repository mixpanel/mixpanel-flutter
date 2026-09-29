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


## Capture and session lifetime boundaries

`ScreenshotCapturer` owns the steps every platform shares: waiting out the
frame in flight, pinning replay identity, mask detection, wireframes, and the
capture result. It delegates pixels to a `FrameAcquirer`:

- `ToImageFrameAcquirer` (native) snapshots the layer tree with
  `RepaintBoundary.toImage()`, paints masks with `MaskPainter`, and hands RGBA
  bytes to an `ImageCompressor`. The snapshot is synchronous with the mask
  walk, so no re-validation is needed.
- `RenderedSurfaceFrameAcquirer` (web) owns the raster budget, waits one
  browser presentation, acquires an immutable `CapturedSurface` through
  `RenderedSurfaceCapture`, and encodes it only after the `MaskLayoutFence`
  confirms the masks still hold. It always disposes the snapshot.
  `WebRenderedSurfaceCapture` owns DOM discovery and presentation waits, while
  `WebImageCompressor` owns the JPEG worker. Encoding consumes a bitmap once;
  rejected snapshots are closed without encoding.

The existing web presentation barriers and endpoint mask comparison remain in
place. This split does not change their treatment of transient layouts that
return to their original geometry between validation points.

`SessionLifetime` owns activity, maximum-duration, and background-retention
deadlines and timers. The coordinator owns recording state, sampling, uploads,
analytics registration, and persistence. It consults wall-clock deadlines at
transitions as well as reacting to timers, since browser suspension can delay
callbacks. Maximum expiry remains active during metadata initialization.
`ResumableSession` keeps a staged session and its persisted deadlines together
while waiting for remote settings.

Web capture requires one matching canvas in one Flutter view. A platform view
may split rendering across multiple canvases; those frames are skipped rather
than selecting an arbitrary surface. Browser tests cover rejection and recovery
when the composition returns to one canvas.
