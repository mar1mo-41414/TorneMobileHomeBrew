/// wakelock_plus-backed [WakelockGuard] (plan 32).
///
/// wakelock_plus flips `UIApplication.isIdleTimerDisabled` on iOS
/// and adds `FLAG_KEEP_SCREEN_ON` to the activity window on
/// Android — exactly the two switches a hand-rolled platform
/// channel would have toggled, with no native code of our own.
/// Failures (e.g. no plugin in a widget test) surface as errors
/// from the calls; [PlaybackWakelock] logs and swallows them.
library;

import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/core.dart';

class WakelockPlusGuard implements WakelockGuard {
  const WakelockPlusGuard();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}
