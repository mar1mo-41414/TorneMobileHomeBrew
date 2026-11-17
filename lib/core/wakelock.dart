/// Sleep suppression while video plays (plan 32, reworked in
/// plan 35).
///
/// Plan 32's first cut followed the player's `playing` stream
/// through wakelock_plus. The build-13 field test (iPhone,
/// LiveContainer) showed two holes, both visible in the debug
/// log of 2026-11-17 13:24:
///
/// 1. **Overlapping sessions dropped the lock.** Playback was
///    started twice about a second apart (the start button stayed
///    live during the ~1.4 s start), so two player screens each
///    drove their own controller against the one OS switch. When
///    the first session ended, its "released" switched the OS
///    lock off while the second session was still playing.
/// 2. **The lock reported success but the device slept anyway.**
///    In the last session the lock was enabled at 13:25:17 and
///    never released, yet the device slept (the `playing=false`
///    at 13:27:39 is the player resurfacing after the wake).
///    wakelock_plus gives no read-back, so there was no way to
///    tell whether the OS had honoured the request at all.
///
/// The rework:
///
/// - [PlaybackWakelock] is now a single app-wide coordinator.
///   Each player screen opens a [WakelockSession]; the OS lock
///   is held while ANY session reports playing, so sessions can
///   overlap and end in any order without dropping it.
/// - [WakelockGuard] implementations must report the state the
///   OS actually holds after a call (read-back), and the
///   coordinator logs it. While the lock is held, a periodic
///   [PlaybackWakelock.verifyNow] re-reads the OS state: if an
///   external actor (the sideload host is the suspect) re-enabled
///   the idle timer, that is logged and the lock is re-applied,
///   so the next field log can pin down where the request goes.
///
/// Behaviour otherwise follows plan 32: pause, stop,
/// end-of-stream and leaving the screen release a session's
/// hold; buffering keeps it (the player still reports playing
/// while it stalls).
///
/// Best-effort by design: a failing platform call is logged and
/// swallowed, never breaking playback itself.
library;

import 'dart:async';

import 'diagnostics.dart';

/// Platform seam for the OS "keep the screen awake" switch.
///
/// Unlike a fire-and-forget toggle, [apply] returns the state
/// the OS reports AFTER the call (read-back), so a platform that
/// silently ignores or overrides the request is visible in the
/// diagnostics log instead of masquerading as success.
abstract interface class WakelockGuard {
  /// Sets the OS keep-awake switch to [keepAwake] and returns
  /// the state the OS reports afterwards (`true` = the device
  /// is being kept awake).
  Future<bool> apply(bool keepAwake);

  /// Returns the keep-awake state the OS currently reports,
  /// without changing it.
  Future<bool> read();
}

/// The app-wide wakelock coordinator (plan 35). Player screens
/// each open a [WakelockSession]; the OS lock follows the union
/// of the sessions' playing states, with platform calls
/// de-duplicated and serialised so rapid flips cannot
/// interleave.
class PlaybackWakelock {
  PlaybackWakelock({
    required WakelockGuard guard,
    DiagLog diag = const DiagLog.none(),
    Duration verifyInterval = const Duration(seconds: 20),
  }) : this._(guard, diag, verifyInterval);

  PlaybackWakelock._(this._guard, this._diag, this._verifyInterval);

  final WakelockGuard _guard;
  final DiagLog _diag;
  final Duration _verifyInterval;

  final Set<WakelockSession> _playingSessions = {};
  bool _held = false;
  Future<void> _chain = Future<void>.value();
  Timer? _verifyTimer;

  /// Whether the lock is currently (logically) held: at least
  /// one session is playing.
  bool get isEnabled => _held;

  /// Opens a hold for one playback session (one player screen).
  WakelockSession openSession() => WakelockSession._(this);

  /// Completes when every queued platform call has finished.
  /// Exposed for tests.
  Future<void> get settled => _chain;

  void _sessionPlayingChanged(WakelockSession session, bool playing) {
    if (playing) {
      _playingSessions.add(session);
    } else {
      _playingSessions.remove(session);
    }
    _sync();
  }

  void _sync() {
    final want = _playingSessions.isNotEmpty;
    if (want == _held) return;
    _held = want;
    _chain = _chain.then((_) => _apply(want));
    _verifyTimer?.cancel();
    _verifyTimer = want
        ? Timer.periodic(
            _verifyInterval,
            (_) => unawaited(verifyNow()),
          )
        : null;
  }

  Future<void> _apply(bool enable) async {
    try {
      final readback = await _guard.apply(enable);
      if (enable) {
        _diag(
          DiagCategory.playback,
          readback
              ? 'wakelock: enabled (playing), os readback=true'
              : 'wakelock: enabled (playing), os readback=false '
                    '(the OS did not honour the request)',
        );
      } else {
        _diag(
          DiagCategory.playback,
          readback
              ? 'wakelock: released (not playing), os readback=true '
                    '(the OS still reports the lock held)'
              : 'wakelock: released (not playing), os readback=false',
        );
      }
    } catch (e) {
      _diag(
        DiagCategory.playback,
        'wakelock: ${enable ? 'enable' : 'release'} failed: $e',
      );
    }
  }

  /// Re-reads the OS state while the lock is held (called
  /// periodically, and directly from tests). If the OS reports
  /// the lock gone — something outside the app re-enabled the
  /// idle timer — that is logged and the lock is re-applied, so
  /// the field log shows both the override and the recovery.
  Future<void> verifyNow() {
    _chain = _chain.then((_) => _verify());
    return _chain;
  }

  Future<void> _verify() async {
    if (!_held) return;
    try {
      final readback = await _guard.read();
      if (readback) return;
      _diag(
        DiagCategory.playback,
        'wakelock: os readback=false while the lock should be '
        'held (the idle timer was re-enabled externally); '
        're-applying',
      );
      final reapplied = await _guard.apply(true);
      _diag(
        DiagCategory.playback,
        'wakelock: re-apply os readback=$reapplied',
      );
    } catch (e) {
      _diag(DiagCategory.playback, 'wakelock: verify failed: $e');
    }
  }
}

/// One playback session's hold on the shared [PlaybackWakelock]
/// (plan 35). Follows the player's playing state; [release]
/// detaches the session for good (the screen is disposed).
class WakelockSession {
  WakelockSession._(this._owner);

  final PlaybackWakelock _owner;
  bool _playing = false;
  bool _released = false;

  /// Follows the player's playing state: [playing] true takes
  /// this session's hold, false drops it. Repeated calls with
  /// the same value are no-ops, as are calls after [release].
  void setPlaying(bool playing) {
    if (_released || playing == _playing) return;
    _playing = playing;
    _owner._sessionPlayingChanged(this, playing);
  }

  /// Detaches the session (screen disposed, playback over),
  /// dropping its hold if it had one. Idempotent.
  void release() {
    if (_released) return;
    _released = true;
    if (_playing) {
      _playing = false;
      _owner._sessionPlayingChanged(this, false);
    }
  }
}
