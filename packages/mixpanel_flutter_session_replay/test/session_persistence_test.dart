import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/logger.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/recording_limits.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/resumable_session.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_lifetime.dart';
import 'package:mixpanel_flutter_session_replay/src/internal/session/session_persistence.dart';
import 'package:mixpanel_flutter_session_replay/src/models/configuration.dart';
import 'package:mixpanel_flutter_session_replay/src/models/session.dart';

void main() {
  group('StoredSessionPersistence', () {
    late List<(String, int, int)> writes;
    late StoredSessionPersistence persistence;

    setUp(() {
      writes = [];
      persistence = StoredSessionPersistence(
        write: (id, idle, max) async {
          writes.add((id, idle, max));
        },
        logger: MixpanelLogger(LogLevel.none),
      );
    });

    SessionLifetime activeLifetime() => SessionLifetime(
      limits: const RecordingDurationLimits(maximum: Duration(hours: 1)),
      onIdleExpired: () {},
      onMaximumExpired: () {},
    )..begin(clock.now());

    test('holds back activity writes within the debounce window', () {
      fakeAsync((async) {
        // GIVEN an activity write that just landed
        final lifetime = activeLifetime();
        persistence.recordActivity('s', lifetime);

        // WHEN more activity follows inside the debounce window
        async.elapse(expiryWriteDebounce - const Duration(milliseconds: 1));
        persistence.recordActivity('s', lifetime);

        // THEN only the first write reached storage
        expect(writes, hasLength(1));

        // AND activity after the window writes again
        async.elapse(const Duration(milliseconds: 1));
        persistence.recordActivity('s', lifetime);
        expect(writes, hasLength(2));
        lifetime.dispose();
      });
    });

    test('writeNow bypasses the debounce', () {
      fakeAsync((async) {
        // GIVEN an activity write that just landed
        final lifetime = activeLifetime();
        persistence.recordActivity('s', lifetime);

        // WHEN a transition forces a write
        persistence.writeNow('s', lifetime);

        // THEN both reached storage
        expect(writes, hasLength(2));
        lifetime.dispose();
      });
    });

    test('writes nothing without a maximum deadline', () {
      // GIVEN a lifetime that has not begun
      final lifetime = SessionLifetime(
        limits: const RecordingDurationLimits(maximum: Duration(hours: 1)),
        onIdleExpired: () {},
        onMaximumExpired: () {},
      );

      // WHEN
      persistence.writeNow('s', lifetime);

      // THEN
      expect(writes, isEmpty);
    });

    test('expire writes deadlines already in the past', () {
      fakeAsync((async) {
        // WHEN
        persistence.expire('s');

        // THEN
        final now = clock.now().millisecondsSinceEpoch;
        expect(writes.single.$1, 's');
        expect(writes.single.$2, lessThan(now));
        expect(writes.single.$3, lessThan(now));
      });
    });

    test('expire resets the debounce for the next activity write', () {
      fakeAsync((async) {
        // GIVEN an activity write followed by an expiry
        final lifetime = activeLifetime();
        persistence.recordActivity('old', lifetime);
        persistence.expire('old');

        // WHEN the next replay records activity right away
        persistence.recordActivity('new', lifetime);

        // THEN it is not held back by the earlier write
        expect(writes.map((write) => write.$1), ['old', 'old', 'new']);
        lifetime.dispose();
      });
    });

    test('offers a staged replay once', () {
      // GIVEN
      final staged = ResumableSession(
        Session(
          id: 'staged',
          startTime: DateTime.utc(2026),
          status: SessionStatus.active,
        ),
      );
      persistence.stageResume(staged);

      // WHEN / THEN
      expect(persistence.takeResumable(), same(staged));
      expect(persistence.takeResumable(), isNull);
      expect(writes, isEmpty);
    });

    test('discarding a staged replay expires its record', () {
      // GIVEN
      persistence.stageResume(
        ResumableSession(
          Session(
            id: 'staged',
            startTime: DateTime.utc(2026),
            status: SessionStatus.active,
          ),
        ),
      );

      // WHEN
      final discarded = persistence.discardResumable();

      // THEN
      expect(discarded!.session.id, 'staged');
      expect(writes.single.$1, 'staged');
      expect(persistence.takeResumable(), isNull);
    });
  });

  test('SessionPersistence.none never offers a replay', () {
    final persistence = SessionPersistence.none();

    expect(persistence.takeResumable(), isNull);
    expect(persistence.discardResumable(), isNull);
  });
}
