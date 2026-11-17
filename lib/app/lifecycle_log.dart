/// App lifecycle transition logging (plan 36).
///
/// The build-14 field test (iPhone, LiveContainer) ended with
/// the device asleep mid-playback although the wakelock's OS
/// read-back was `true` at enable time and no verify anomaly was
/// ever recorded. Two very different stories fit that log: the
/// app was suspended by the host before it could notice anything,
/// or the idle timer came back without the verify seeing it.
/// Telling them apart needs the app's own lifecycle transitions
/// in the same log: on iOS a sleep walks the app through
/// inactive -> hidden -> paused, and the wake walks it back, so
/// the timestamps (and the gap between them) show when the
/// process stopped and resumed relative to the playback records.
///
/// Records go under the playback category: the transitions that
/// matter are the ones around playback, and the field workflow
/// enables that category for wakelock diagnosis, so the two
/// record streams land in the same slice of the log. The sink
/// stamps each line when the record is made (not when the write
/// lands), so a transition queued just before a suspension still
/// carries the transition's own time.
library;

import 'package:flutter/widgets.dart';

import '../core/core.dart';

/// A [WidgetsBindingObserver] that writes every app lifecycle
/// transition to the diagnostics log. Attach once at startup;
/// the binding holds the observer for the app's lifetime.
class LifecycleLogger extends WidgetsBindingObserver {
  LifecycleLogger(this._diag);

  final DiagLog _diag;

  /// Starts observing. The observer is never detached: it lives
  /// exactly as long as the app.
  void attach() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _diag(DiagCategory.playback, 'app lifecycle: ${state.name}');
  }
}
