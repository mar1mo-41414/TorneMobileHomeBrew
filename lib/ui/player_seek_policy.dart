/// Player seek policy (player UI follow-up after 1.4.0):
/// the ±10-second skip buttons on the recorded playback
/// screen, and the terms on which they may act.
///
/// The buttons seek only while mpv reports the stream
/// seekable (its `seekable` property). That gate is not
/// decorative: the loopback proxy serves every stream —
/// recordings included — as a chunked response without a
/// content length and without ranges (see dtcp_playback),
/// so mpv marks the stream not seekable and a seek command
/// is refused with "Cannot seek in this stream." (plan 43).
/// With today's proxy the buttons therefore stay disabled;
/// they are wired to the real signal so that a seekable
/// source feeding this screen later enables them with no
/// further UI work, and so that an unseekable stream shows
/// a disabled button rather than inviting a refused seek.
///
/// A refusal can still reach the screen after the fact (a
/// seek issued just as the stream's seekability lapses);
/// once playback has started it is non-fatal, like the
/// live case (see player_error_policy).
library;

/// The step the recorded screen's skip buttons seek by:
/// ten seconds back, ten seconds forward.
const Duration skipSeekStep = Duration(seconds: 10);

/// Whether an mpv `seekable` property value reports a
/// seekable stream. mpv answers "yes" / "no"; anything
/// else (an empty string before the demuxer settles, an
/// unknown value) counts as not seekable, so the buttons
/// start disabled and light up only on a definite yes.
bool isSeekablePropertyValue(String? value) => value == 'yes';

/// The position a skip of [offset] (plus or minus
/// [skipSeekStep]) from [position] lands on, clamped to
/// the stream: never before zero, and never past
/// [duration] when the duration is known. Streams whose
/// duration mpv does not know report zero; their skips
/// clamp only at zero and let mpv judge the far end.
Duration skipSeekTarget({
  required Duration position,
  required Duration offset,
  required Duration duration,
}) {
  final target = position + offset;
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}
