/// Sleep suppression while video plays (plan 32).
///
/// On the build-10 field test the user watched on an iPad for
/// about five minutes and the device tried to sleep mid-playback:
/// nothing ever disabled the OS idle timer. This file is the
/// platform-free half of the fix — a [WakelockGuard] seam (the app
/// layer backs it with wakelock_plus, which flips iOS
/// `UIApplication.isIdleTimerDisabled` and Android's
/// `FLAG_KEEP_SCREEN_ON`) and [PlaybackWakelock], the state
/// tracker the player screen drives from the player's `playing`
/// stream.
///
/// Behaviour: the lock is held exactly while the player reports
/// playing. Pause, stop, end-of-stream and leaving the screen all
/// release it. Buffering keeps the lock (the player still reports
/// playing while it stalls), which is what a viewer expects when
/// a slow path makes playback pause and resume on its own.
///
/// Best-effort by design: a failing platform call is logged and
/// swallowed, never breaking playback itself.
library;

import 'diagnostics.dart';

/// Platform seam for the OS "keep the screen awake" switch.
abstract interface class WakelockGuard {
  /// Prevents the device from sleeping.
  Future<void> enable();

  /// Restores the normal idle-timer behaviour.
  Future<void> disable();
}

/// Keeps a [WakelockGuard] in sync with the player's playing
/// state, de-duplicating transitions and serialising the platform
/// calls so rapid play/pause flips cannot interleave.
class PlaybackWakelock {
  PlaybackWakelock({
    required WakelockGuard guard,
    DiagLog diag = const DiagLog.none(),
  }) : this._(guard, diag);

  PlaybackWakelock._(this._guard, this._diag);

  final WakelockGuard _guard;
  final DiagLog _diag;

  bool _enabled = false;
  Future<void> _chain = Future<void>.value();

  /// Whether the lock is currently (logically) held.
  bool get isEnabled => _enabled;

  /// Follows the player's playing state: [playing] true holds the
  /// lock, false releases it. Repeated calls with the same value
  /// are no-ops.
  void setPlaying(bool playing) {
    if (playing == _enabled) return;
    _enabled = playing;
    _chain = _chain.then((_) => _apply(playing));
  }

  /// Releases the lock if held (screen disposed, playback over).
  void release() => setPlaying(false);

  /// Completes when every queued platform call has finished.
  /// Exposed for tests.
  Future<void> get settled => _chain;

  Future<void> _apply(bool enable) async {
    try {
      if (enable) {
        await _guard.enable();
        _diag(DiagCategory.playback, 'wakelock: enabled (playing)');
      } else {
        await _guard.disable();
        _diag(DiagCategory.playback, 'wakelock: released (not playing)');
      }
    } catch (e) {
      _diag(
        DiagCategory.playback,
        'wakelock: ${enable ? 'enable' : 'release'} failed: $e',
      );
    }
  }
}
