/// Keeping media_kit's mpv initialization from hanging on
/// older Android (plan 139).
///
/// Field report (Fire TV 4K Max first generation, Fire OS 7 =
/// Android 9 / API 28): playback never started — the debug log
/// showed 'player: opening …' and then nothing until the
/// plan-29 start watchdog fired at 45 s. The nasne side was
/// healthy: the proxy filled its prefetch cap with decrypted
/// content, and the player never connected to the proxy at all.
/// The app's own log showed execution stopping at the first
/// awaited setProperty after 'player: opening'.
///
/// media_kit 1.2.6's async initialization (the default) sets
/// its initial properties (26 of them in the default
/// configuration) through mpv's async property API and waits
/// for every reply event. On this generation of Android the
/// native initializer takes the NativeCallable path (its
/// execmem probe succeeds there), which registers mpv's
/// wakeup callback without draining events that queued before
/// registration; a reply landing in that window may never be
/// delivered, and the initialization wait — and with it the
/// first setProperty of an open, and dispose, which also
/// waits for initialization — never completes. (Which side of
/// the libmpv boundary the lost wakeup sits on was not
/// isolated from the Dart sources; the code-side premises —
/// the all-replies wait, the missing drain — are read off
/// media_kit 1.2.6 itself.)
///
/// The countermeasure has two parts, both confined to
/// Android at API 28 or below; API 29 and later take the
/// Isolate initializer and are untouched:
///
///  * The player is created with
///    PlayerConfiguration(async: false), so property sets and
///    commands run synchronously against mpv and no call waits
///    on event delivery. This is the part that removes the
///    hang: it does not depend on the exact race above being
///    the whole story.
///  * [kickMpvEventLoop] pokes mpv_wakeup once after creation
///    and once before open, as a backstop: if anything is
///    parked waiting for an event, the poke gives it a chance
///    to drain. mpv_wakeup is documented for threads waiting
///    in mpv_wait_event, so the kick is insurance, not the
///    fix, and its delivery is logged either way.
///
/// The arrangement was first shipped by the nullpon19 fork
/// (v1.5.0-firetv.3) and confirmed on the reporting device;
/// this is the same arrangement in this codebase's shape
/// (MIT to MIT).
library;

import 'dart:ffi';
import 'dart:io';

/// The newest Android SDK int the legacy sync init applies
/// to: API 28 (Android 9), the last generation whose media_kit
/// initializer takes the NativeCallable path (see the library
/// comment). API 29+ is deliberately untouched.
const int legacySyncMpvInitMaxSdkInt = 28;

/// Whether the player must be created with media_kit's
/// synchronous property path: Android at
/// [legacySyncMpvInitMaxSdkInt] or below. An unknown SDK int
/// (null — the platform did not answer) is NOT legacy: the
/// async default is the behaviour every current install runs,
/// and only a positively known old device changes it.
bool shouldUseLegacySyncMpvInit({
  required bool isAndroid,
  required int? androidSdkInt,
}) =>
    isAndroid &&
    androidSdkInt != null &&
    androidSdkInt <= legacySyncMpvInitMaxSdkInt;

typedef _MpvWakeupNative = Void Function(Pointer<Void>);
typedef _MpvWakeupDart = void Function(Pointer<Void>);

_MpvWakeupDart? _mpvWakeup;

/// Pokes libmpv's event loop once for the player behind
/// [handle] (the value of media_kit's Player.handle). Returns
/// whether the poke was delivered; false — not Android,
/// libmpv not loadable under that name, the symbol missing,
/// any FFI failure — is a normal answer and is for the caller
/// to log, never an exception. [handle] must be a live player
/// handle: the caller owns that guarantee (the player screen
/// only kicks its own player, and only on the legacy path,
/// where the handle getter's initialization wait completes).
bool kickMpvEventLoop(int handle) {
  if (!Platform.isAndroid) return false;
  try {
    final wakeup = _mpvWakeup ??= DynamicLibrary.open('libmpv.so')
        .lookupFunction<_MpvWakeupNative, _MpvWakeupDart>('mpv_wakeup');
    wakeup(Pointer.fromAddress(handle));
    return true;
  } catch (_) {
    return false;
  }
}
