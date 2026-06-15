import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/settings/settings_service.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/debug_overlay_colors.dart';
import 'package:mixpanel_flutter_session_replay/src/models/masking_directive.dart';
import 'package:mixpanel_flutter_session_replay/src/models/results.dart';
import 'package:mixpanel_flutter_session_replay/src/session_replay.dart';
import 'package:mixpanel_flutter_session_replay/src/session_replay_options.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/frame_monitor.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/interaction_detector.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/lifecycle_observer.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/mask_overlay.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/mask_widget.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/session_replay_widget.dart';
import 'package:mixpanel_flutter_session_replay/src/widgets/unmask_widget.dart';

import 'helpers/fake_widget_coordinator.dart';
import 'helpers/in_memory_event_queue.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // MixpanelMask / MixpanelUnmask (no dependencies needed)
  // ─────────────────────────────────────────────────────────────────────
  group('MixpanelMask', () {
    testWidgets('renders its child', (tester) async {
      // GIVEN
      const expectedText = 'Sensitive Data';

      // WHEN
      await tester.pumpWidget(
        const MaterialApp(home: MixpanelMask(child: Text(expectedText))),
      );

      // THEN
      expect(find.text(expectedText), findsOneWidget);
      expect(find.byType(MixpanelMask), findsOneWidget);
    });

    testWidgets('is transparent to widget tree structure', (tester) async {
      // GIVEN / WHEN
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              MixpanelMask(child: Text('A')),
              Text('B'),
            ],
          ),
        ),
      );

      // THEN
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });

  group('MixpanelUnmask', () {
    testWidgets('renders its child', (tester) async {
      // GIVEN
      const expectedText = 'Public Data';

      // WHEN
      await tester.pumpWidget(
        const MaterialApp(home: MixpanelUnmask(child: Text(expectedText))),
      );

      // THEN
      expect(find.text(expectedText), findsOneWidget);
      expect(find.byType(MixpanelUnmask), findsOneWidget);
    });

    testWidgets('can nest inside MixpanelMask', (tester) async {
      // GIVEN / WHEN
      await tester.pumpWidget(
        const MaterialApp(
          home: MixpanelMask(
            child: Column(
              children: [
                Text('Masked'),
                MixpanelUnmask(child: Text('Unmasked')),
              ],
            ),
          ),
        ),
      );

      // THEN
      expect(find.text('Masked'), findsOneWidget);
      expect(find.text('Unmasked'), findsOneWidget);
      expect(find.byType(MixpanelMask), findsOneWidget);
      expect(find.byType(MixpanelUnmask), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // InteractionDetector (using FakeWidgetCoordinator)
  // ─────────────────────────────────────────────────────────────────────
  group('InteractionDetector', () {
    testWidgets('wraps child in Listener', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: InteractionDetector(
            coordinator: fake,
            child: const Text('Hello'),
          ),
        ),
      );

      // THEN
      expect(find.byType(Listener), findsWidgets);
      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('ignores pointer when not recording', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.notRecording,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InteractionDetector(
            coordinator: fake,
            child: Container(
              width: 200,
              height: 200,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      );

      // WHEN
      final center = tester.getCenter(find.byType(Container));
      await tester.tapAt(center);
      await tester.pump();

      // THEN - no interaction captured
      expect(fake.capturedInteractions, isEmpty);
    });

    testWidgets('dispatches touch pointer to coordinator when recording', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.recording,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InteractionDetector(
            coordinator: fake,
            child: Container(
              width: 200,
              height: 200,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      );

      // WHEN
      final center = tester.getCenter(find.byType(Container));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.touch);
      await gesture.down(center);
      await tester.pump();
      await gesture.up();

      // THEN - interaction captured
      expect(fake.capturedInteractions.length, 1);
    });

    testWidgets('dispatches mouse pointer to coordinator when recording', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.recording,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InteractionDetector(
            coordinator: fake,
            child: Container(
              width: 200,
              height: 200,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      );

      // WHEN
      final center = tester.getCenter(find.byType(Container));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(center);
      await tester.pump();
      await gesture.up();

      // THEN
      expect(fake.capturedInteractions.length, 1);
    });

    testWidgets('does not dispatch stylus pointer events', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.recording,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InteractionDetector(
            coordinator: fake,
            child: Container(
              width: 200,
              height: 200,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      );

      // WHEN - stylus pointer (should be filtered by kind check)
      final center = tester.getCenter(find.byType(Container));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.stylus,
      );
      await gesture.down(center);
      await tester.pump();
      await gesture.up();

      // THEN - no interaction captured (stylus is filtered out)
      expect(fake.capturedInteractions, isEmpty);
    });

    testWidgets('ignores pointer when settings are disabled', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        remoteEnablementState: RemoteEnablementState.disabled,
        recordingState: RecordingState.recording,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: InteractionDetector(
            coordinator: fake,
            child: Container(
              width: 200,
              height: 200,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ),
      );

      // WHEN
      final center = tester.getCenter(find.byType(Container));
      await tester.tapAt(center);
      await tester.pump();

      // THEN - no interaction captured (disabled check comes first)
      expect(fake.capturedInteractions, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // LifecycleObserver (using FakeWidgetCoordinator)
  // ─────────────────────────────────────────────────────────────────────
  group('LifecycleObserver', () {
    testWidgets('renders its child', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: LifecycleObserver(
            coordinator: fake,
            child: const Text('Content'),
          ),
        ),
      );

      // THEN
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets(
      'calls onAppForegrounded when lifecycle transitions to resumed',
      (tester) async {
        // GIVEN
        final fake = FakeWidgetCoordinator();

        await tester.pumpWidget(
          MaterialApp(
            home: LifecycleObserver(coordinator: fake, child: const SizedBox()),
          ),
        );

        // WHEN
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        // THEN
        expect(fake.onAppForegroundedCallCount, 1);
      },
    );

    testWidgets(
      'calls onAppBackgrounded when transitioning from resumed to inactive',
      (tester) async {
        // GIVEN
        final fake = FakeWidgetCoordinator();

        await tester.pumpWidget(
          MaterialApp(
            home: LifecycleObserver(coordinator: fake, child: const SizedBox()),
          ),
        );

        // Establish resumed state first so the observer has a valid _lastState
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(fake.onAppForegroundedCallCount, 1);

        // WHEN - transition to inactive
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();

        // THEN
        expect(fake.onAppBackgroundedCallCount, 1);
      },
    );

    testWidgets('calls onAppForegrounded when resuming from inactive', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: LifecycleObserver(coordinator: fake, child: const SizedBox()),
        ),
      );

      // Drive to resumed then inactive
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(fake.onAppForegroundedCallCount, 1);
      expect(fake.onAppBackgroundedCallCount, 1);

      // WHEN - resume again
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // THEN
      expect(fake.onAppForegroundedCallCount, 2);
    });

    testWidgets('full lifecycle: resumed -> inactive -> paused -> resumed', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: LifecycleObserver(coordinator: fake, child: const SizedBox()),
        ),
      );

      // Establish resumed state
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.onAppForegroundedCallCount, 1);

      // WHEN - full background cycle
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(fake.onAppBackgroundedCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // paused is less visible than inactive, so no additional background call
      expect(fake.onAppBackgroundedCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.onAppForegroundedCallCount, 2);
    });

    testWidgets(
      'does not call onAppBackgrounded when going from paused to inactive',
      (tester) async {
        // GIVEN - inactive is MORE visible than paused, so this is "coming up"
        final fake = FakeWidgetCoordinator();

        await tester.pumpWidget(
          MaterialApp(
            home: LifecycleObserver(coordinator: fake, child: const SizedBox()),
          ),
        );

        // Drive: resumed -> inactive -> paused
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(
          fake.onAppBackgroundedCallCount,
          1,
        ); // Only from resumed->inactive

        // WHEN - paused -> inactive (going UP in visibility)
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();

        // THEN - no additional background call (inactive is more visible than paused)
        expect(fake.onAppBackgroundedCallCount, 1);
      },
    );

    testWidgets('removes observer on dispose without crash', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: LifecycleObserver(coordinator: fake, child: const SizedBox()),
        ),
      );

      // WHEN - dispose by replacing widget tree
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // THEN - lifecycle changes after disposal don't crash or trigger callbacks
      final callsBefore = fake.onAppBackgroundedCallCount;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(fake.onAppBackgroundedCallCount, callsBefore);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // MaskOverlay (no coordinator dependency)
  // ─────────────────────────────────────────────────────────────────────
  group('MaskOverlay', () {
    testWidgets('renders child in a Stack with IgnorePointer', (tester) async {
      // GIVEN
      const colors = DebugOverlayColors();

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: MaskOverlay(
            maskRegions: const [],
            colors: colors,
            child: const Text('Under Overlay'),
          ),
        ),
      );

      // THEN
      expect(find.text('Under Overlay'), findsOneWidget);
      expect(find.byType(Stack), findsWidgets);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(IgnorePointer), findsWidgets);
    });

    testWidgets('renders with all mask source types', (tester) async {
      // GIVEN
      const colors = DebugOverlayColors();
      final maskRegions = [
        MaskRegionInfo(const Rect.fromLTWH(10, 10, 100, 50), MaskSource.auto),
        MaskRegionInfo(const Rect.fromLTWH(10, 70, 100, 50), MaskSource.manual),
        MaskRegionInfo(
          const Rect.fromLTWH(10, 130, 100, 50),
          MaskSource.unmask,
        ),
        MaskRegionInfo(
          const Rect.fromLTWH(10, 190, 100, 50),
          MaskSource.security,
        ),
      ];

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: MaskOverlay(
              maskRegions: maskRegions,
              colors: colors,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // THEN
      expect(find.byType(MaskOverlay), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('skips drawing when mask color is null', (tester) async {
      // GIVEN - auto mask color disabled
      const colors = DebugOverlayColors(
        autoMaskColor: null,
        maskColor: Color(0xFFFF0000),
        unmaskColor: Color(0xFF00FF00),
      );
      final maskRegions = [
        MaskRegionInfo(const Rect.fromLTWH(10, 10, 100, 50), MaskSource.auto),
      ];

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: MaskOverlay(
              maskRegions: maskRegions,
              colors: colors,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // THEN - renders without error (null color = skipped)
      expect(find.byType(MaskOverlay), findsOneWidget);
    });

    testWidgets('repaints when mask regions change', (tester) async {
      // GIVEN - empty initial regions
      const colors = DebugOverlayColors();

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: MaskOverlay(
              maskRegions: const [],
              colors: colors,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // WHEN - update with new regions
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 400,
            child: MaskOverlay(
              maskRegions: [
                MaskRegionInfo(
                  const Rect.fromLTWH(0, 0, 50, 50),
                  MaskSource.auto,
                ),
              ],
              colors: colors,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      // THEN
      expect(find.byType(MaskOverlay), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // FrameMonitor (using FakeWidgetCoordinator)
  // ─────────────────────────────────────────────────────────────────────
  group('FrameMonitor', () {
    testWidgets('renders child inside RepaintBoundary', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();
      final frameNotifier = ChangeNotifier();

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const Text('Monitored'),
          ),
        ),
      );

      // THEN
      expect(find.text('Monitored'), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('ignores frame notifications when not recording', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.notRecording,
      );
      final frameNotifier = ChangeNotifier();

      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const SizedBox(),
          ),
        ),
      );

      // WHEN - notify frame change while not recording
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      frameNotifier.notifyListeners();
      await tester.pump();

      // THEN - no capture attempted
      expect(fake.captureSnapshotCallCount, 0);
    });

    testWidgets('ignores frame notifications when settings disabled', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        remoteEnablementState: RemoteEnablementState.disabled,
        recordingState: RecordingState.recording,
      );
      final frameNotifier = ChangeNotifier();

      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const SizedBox(),
          ),
        ),
      );

      // WHEN
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      frameNotifier.notifyListeners();
      await tester.pump();

      // THEN - no capture attempted
      expect(fake.captureSnapshotCallCount, 0);
    });

    testWidgets('ignores frame notifications when app backgrounded', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.recording,
        isAppInForeground: false,
      );
      final frameNotifier = ChangeNotifier();

      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const SizedBox(),
          ),
        ),
      );

      // WHEN
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      frameNotifier.notifyListeners();
      await tester.pump();

      // THEN - no capture attempted
      expect(fake.captureSnapshotCallCount, 0);
    });

    testWidgets('captures snapshot on initial frame when recording', (
      tester,
    ) async {
      // GIVEN - all conditions favorable for capture from the start
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.recording,
      );
      final frameNotifier = ChangeNotifier();

      // WHEN - pump widget (triggers initState's addPostFrameCallback)
      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();

      // THEN - initial post-frame callback triggered a capture
      expect(fake.captureSnapshotCallCount, 1);
    });

    testWidgets(
      'captures snapshot when frame notification received while recording',
      (tester) async {
        // GIVEN - start not recording so initial callback doesn't capture
        final fake = FakeWidgetCoordinator(
          recordingState: RecordingState.notRecording,
        );
        final frameNotifier = ChangeNotifier();

        await tester.pumpWidget(
          MaterialApp(
            home: FrameMonitor(
              frameNotifier: frameNotifier,
              coordinator: fake,
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        );
        await tester.pump();
        expect(fake.captureSnapshotCallCount, 0);

        // WHEN - switch to recording and notify a frame change
        fake.recordingState = RecordingState.recording;
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        frameNotifier.notifyListeners();
        await tester.pump();

        // THEN - capture triggered via _onFrame -> _attemptCapture -> _triggerCapture
        expect(fake.captureSnapshotCallCount, 1);
      },
    );

    testWidgets('rate limits captures within cooldown period', (tester) async {
      // GIVEN - recording from start, initial capture fires
      final fake = FakeWidgetCoordinator(
        recordingState: RecordingState.recording,
      );
      final frameNotifier = ChangeNotifier();

      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      await tester.pump();
      expect(fake.captureSnapshotCallCount, 1);

      // WHEN - trigger another frame notification immediately (within 500ms cooldown)
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      frameNotifier.notifyListeners();
      await tester.pump();

      // THEN - rate limited: scheduler.canCapture() returns false,
      // so scheduleAfterRateLimit is called instead of _triggerCapture
      expect(fake.captureSnapshotCallCount, 1);
    });

    testWidgets('renders debug mask overlay when debugOptions provided', (
      tester,
    ) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();
      final frameNotifier = ChangeNotifier();
      const debugOptions = DebugOptions();

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            debugOptions: debugOptions,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );

      // THEN - debug overlay should be rendered (kDebugMode is true in tests)
      expect(find.byType(MaskOverlay), findsOneWidget);
    });

    testWidgets('cleans up listener on dispose', (tester) async {
      // GIVEN
      final fake = FakeWidgetCoordinator();
      final frameNotifier = ChangeNotifier();

      await tester.pumpWidget(
        MaterialApp(
          home: FrameMonitor(
            frameNotifier: frameNotifier,
            coordinator: fake,
            child: const SizedBox(),
          ),
        ),
      );

      // WHEN - dispose widget
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // THEN - notifying after dispose doesn't crash
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      frameNotifier.notifyListeners();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // MixpanelSessionReplayWidget (integration tests — uses real instance)
  // ─────────────────────────────────────────────────────────────────────
  group('MixpanelSessionReplayWidget', () {
    testWidgets('renders child when instance is null', (tester) async {
      // GIVEN / WHEN
      await tester.pumpWidget(
        const MaterialApp(
          home: MixpanelSessionReplayWidget(
            instance: null,
            child: Text('My App'),
          ),
        ),
      );

      // THEN - child rendered directly without monitoring widgets
      expect(find.text('My App'), findsOneWidget);
      expect(find.byType(LifecycleObserver), findsNothing);
      expect(find.byType(InteractionDetector), findsNothing);
      expect(find.byType(FrameMonitor), findsNothing);
    });

    testWidgets('wraps child in monitoring widgets when instance provided', (
      tester,
    ) async {
      // GIVEN
      final queue = InMemoryEventQueue();
      await queue.initialize();
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'widget-test',
        distinctId: 'user-1',
        options: SessionReplayOptions(
          logLevel: LogLevel.none,
          flushInterval: Duration(hours: 1),
        ),
        eventQueue: queue,
      );
      final instance = result.instance!;

      // WHEN
      await tester.pumpWidget(
        MaterialApp(
          home: MixpanelSessionReplayWidget(
            instance: instance,
            child: const Text('My App'),
          ),
        ),
      );

      // THEN
      expect(find.text('My App'), findsOneWidget);
      expect(find.byType(LifecycleObserver), findsOneWidget);
      expect(find.byType(InteractionDetector), findsOneWidget);
      expect(find.byType(FrameMonitor), findsOneWidget);
    });

    testWidgets('transitions from null to non-null instance', (tester) async {
      // GIVEN - start with null instance
      await tester.pumpWidget(
        const MaterialApp(
          home: MixpanelSessionReplayWidget(
            instance: null,
            child: Text('My App'),
          ),
        ),
      );
      expect(find.byType(LifecycleObserver), findsNothing);

      // Create instance
      final queue = InMemoryEventQueue();
      await queue.initialize();
      final result = await MixpanelSessionReplay.initializeWithDependencies(
        token: 'transition-test',
        distinctId: 'user-1',
        options: SessionReplayOptions(
          logLevel: LogLevel.none,
          flushInterval: Duration(hours: 1),
        ),
        eventQueue: queue,
      );
      final instance = result.instance!;

      // WHEN - update with non-null instance
      await tester.pumpWidget(
        MaterialApp(
          home: MixpanelSessionReplayWidget(
            instance: instance,
            child: const Text('My App'),
          ),
        ),
      );

      // THEN
      expect(find.text('My App'), findsOneWidget);
      expect(find.byType(LifecycleObserver), findsOneWidget);
      expect(find.byType(InteractionDetector), findsOneWidget);
      expect(find.byType(FrameMonitor), findsOneWidget);
    });

    testWidgets('disposes cleanly', (tester) async {
      // GIVEN
      await tester.pumpWidget(
        const MaterialApp(
          home: MixpanelSessionReplayWidget(
            instance: null,
            child: Text('My App'),
          ),
        ),
      );

      // WHEN - replace with different widget
      await tester.pumpWidget(const MaterialApp(home: Text('Replaced')));

      // THEN
      expect(find.text('Replaced'), findsOneWidget);
    });
  });
}
