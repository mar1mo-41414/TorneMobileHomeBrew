/// Playback wakelock tests (plan 32): the lock follows the
/// player's playing state, transitions are de-duplicated and
/// serialised, release is idempotent, and a failing platform
/// guard is logged instead of breaking playback.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

class FakeWakelockGuard implements WakelockGuard {
  final List<String> calls = [];
  Object? errorOnEnable;
  Object? errorOnDisable;

  @override
  Future<void> enable() async {
    calls.add('enable');
    final error = errorOnEnable;
    if (error != null) throw error;
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    final error = errorOnDisable;
    if (error != null) throw error;
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
      );
    });

    test('playing enables the lock once; repeats are no-ops', () async {
      wakelock.setPlaying(true);
      wakelock.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['enable']);
      expect(wakelock.isEnabled, isTrue);
      expect(records, ['playback: wakelock: enabled (playing)']);
    });

    test('pause releases the lock', () async {
      wakelock.setPlaying(true);
      await wakelock.settled;
      wakelock.setPlaying(false);
      await wakelock.settled;
      expect(guard.calls, ['enable', 'disable']);
      expect(wakelock.isEnabled, isFalse);
      expect(records, [
        'playback: wakelock: enabled (playing)',
        'playback: wakelock: released (not playing)',
      ]);
    });

    test('not-playing from the start never touches the guard', () async {
      wakelock.setPlaying(false);
      wakelock.release();
      await wakelock.settled;
      expect(guard.calls, isEmpty);
      expect(records, isEmpty);
    });

    test('rapid flips are serialised in order', () async {
      wakelock.setPlaying(true);
      wakelock.setPlaying(false);
      wakelock.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['enable', 'disable', 'enable']);
      expect(wakelock.isEnabled, isTrue);
    });

    test('release after playback disables exactly once', () async {
      wakelock.setPlaying(true);
      await wakelock.settled;
      wakelock.release();
      wakelock.release();
      await wakelock.settled;
      expect(guard.calls, ['enable', 'disable']);
    });

    test('a failing enable is logged, not thrown', () async {
      guard.errorOnEnable = StateError('no plugin');
      wakelock.setPlaying(true);
      await wakelock.settled;
      expect(guard.calls, ['enable']);
      expect(records, hasLength(1));
      expect(records.single, contains('wakelock: enable failed'));
      expect(records.single, contains('no plugin'));
    });

    test('a failing release is logged, not thrown', () async {
      wakelock.setPlaying(true);
      await wakelock.settled;
      guard.errorOnDisable = StateError('gone');
      wakelock.setPlaying(false);
      await wakelock.settled;
      expect(guard.calls, ['enable', 'disable']);
      expect(records.last, contains('wakelock: release failed'));
    });
  });
}
