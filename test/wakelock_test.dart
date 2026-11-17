/// Playback wakelock tests (plan 32, reworked in plan 35): the
/// OS lock is held while ANY playback session is playing, the
/// guard's read-back is logged, an external override detected by
/// the periodic verify is logged and re-applied, and a failing
/// platform guard is logged instead of breaking playback.
///
/// The overlap cases are the regression test for the build-13
/// field log (2026-11-17 13:24): two sessions overlapped and the
/// first one's release dropped the lock under the second.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

/// A guard that plays back a scripted OS: [osState] is what the
/// platform "actually" holds; tests can flip it directly to
/// simulate an external actor re-enabling the idle timer.
class FakeWakelockGuard implements WakelockGuard {
  final List<String> calls = [];
  bool osState = false;
  Object? errorOnApply;
  Object? errorOnRead;

  /// When non-null, apply() reports this read-back instead of
  /// the state it just set (a platform that ignores requests).
  bool? applyReadbackOverride;

  @override
  Future<bool> apply(bool keepAwake) async {
    calls.add('apply($keepAwake)');
    final error = errorOnApply;
    if (error != null) throw error;
    osState = keepAwake;
    return applyReadbackOverride ?? osState;
  }

  @override
  Future<bool> read() async {
    calls.add('read()');
    final error = errorOnRead;
    if (error != null) throw error;
    return osState;
  }
}

void main() {
  group('PlaybackWakelock', () {
    late FakeWakelockGuard guard;
    late List<String> records;
    late PlaybackWakelock wakelock;

    setUp(() {
      guard = FakeWakelockGuard();
      records = [];
      wakelock = PlaybackWakelock(
        guard: guard,
        diag: DiagLog(
          (category, message) => records.add('${category.name}: $message'),
          (_) => true,
        ),
        // The periodic verify must not fire during a test;
        // verifyNow() is driven directly instead.
        verifyInterval: const Duration(days: 1),
      );
    });

    test('one session: playing enables once; repeats are no-ops', () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      session.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)']);
      expect(wakelock.isEnabled, isTrue);
      expect(records, ['playback: wakelock: enabled (playing), os readback=true']);
    });

    test('one session: pause releases the lock', () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      session.setPlaying(false);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)', 'apply(false)']);
      expect(wakelock.isEnabled, isFalse);
      expect(records, [
        'playback: wakelock: enabled (playing), os readback=true',
        'playback: wakelock: released (not playing), os readback=false',
      ]);
    });

    test('a session that never plays never touches the guard', () async {
      final session = wakelock.openSession();
      session.setPlaying(false);
      session.release();
      await wakelock.settled;
      expect(guard.calls, isEmpty);
      expect(records, isEmpty);
    });

    test('overlap: the first session ending keeps the lock for the '
        'second (build-13 field-log regression)', () async {
      final first = wakelock.openSession();
      final second = wakelock.openSession();
      first.setPlaying(true);
      await wakelock.settled;
      second.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)']);

      // The first session ends (its screen is disposed) while
      // the second is still playing: no release may reach the OS.
      first.release();
      await wakelock.settled;
      expect(guard.calls, ['apply(true)']);
      expect(wakelock.isEnabled, isTrue);

      second.setPlaying(false);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)', 'apply(false)']);
      expect(wakelock.isEnabled, isFalse);
    });

    test('overlap: sessions may stop in any order', () async {
      final first = wakelock.openSession();
      final second = wakelock.openSession();
      first.setPlaying(true);
      second.setPlaying(true);
      await wakelock.settled;
      second.release();
      await wakelock.settled;
      expect(guard.calls, ['apply(true)']);
      first.setPlaying(false);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)', 'apply(false)']);
    });

    test('release is idempotent and a released session is inert',
        () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      session.release();
      session.release();
      session.setPlaying(true); // ignored: session is detached
      await wakelock.settled;
      expect(guard.calls, ['apply(true)', 'apply(false)']);
      expect(wakelock.isEnabled, isFalse);
    });

    test('rapid flips across sessions are serialised in order',
        () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      session.setPlaying(false);
      session.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)', 'apply(false)', 'apply(true)']);
      expect(wakelock.isEnabled, isTrue);
    });

    test('an enable the OS does not honour is visible in the log',
        () async {
      guard.applyReadbackOverride = false;
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)']);
      expect(records, hasLength(1));
      expect(records.single, contains('os readback=false'));
      expect(records.single, contains('did not honour'));
    });

    test('verifyNow: an external override is logged and re-applied',
        () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      // Something outside the app re-enables the idle timer.
      guard.osState = false;
      await wakelock.verifyNow();
      expect(guard.calls, ['apply(true)', 'read()', 'apply(true)']);
      expect(guard.osState, isTrue);
      expect(
        records,
        contains(
          'playback: wakelock: os readback=false while the lock '
          'should be held (the idle timer was re-enabled '
          'externally); re-applying',
        ),
      );
      expect(records.last, 'playback: wakelock: re-apply os readback=true');
    });

    test('verifyNow: a held lock that reads back fine stays quiet',
        () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      records.clear();
      await wakelock.verifyNow();
      expect(guard.calls, ['apply(true)', 'read()']);
      expect(records, isEmpty);
    });

    test('verifyNow: nothing to verify while the lock is not held',
        () async {
      await wakelock.verifyNow();
      expect(guard.calls, isEmpty);
      expect(records, isEmpty);
    });

    test('a failing enable is logged, not thrown', () async {
      guard.errorOnApply = StateError('no plugin');
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['apply(true)']);
      expect(records, hasLength(1));
      expect(records.single, contains('wakelock: enable failed'));
      expect(records.single, contains('no plugin'));
    });

    test('a failing verify is logged, not thrown', () async {
      final session = wakelock.openSession();
      session.setPlaying(true);
      await wakelock.settled;
      guard.errorOnRead = StateError('gone');
      await wakelock.verifyNow();
      expect(records.last, contains('wakelock: verify failed'));
    });
  });
}
