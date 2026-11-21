/// Player resume-report policy (plan 102): what position a
/// finished recorded viewing reports back to the unit, whose
/// resume point is what a later "continue" — in this app or
/// in the official client — starts from.
///
/// The report is the only way the unit learns a position
/// from this app: its DTCP serving does not track the
/// playhead (measured in plan 102 — after HB playbacks the
/// unit's points were all still zero), so without it the
/// resume offer of plan 86 could only ever fire for titles
/// the official client had played.
///
/// The terms:
/// - A viewing that never started reports nothing. A failed
///   start must not erase a point an earlier viewing left:
///   the unit's point is only replaced by a viewing that
///   actually played.
/// - A viewing that ran to the end reports zero, which
///   clears the point. The unit does not normalise an
///   at-or-past-the-end position itself (measured: positions
///   far past the duration are stored verbatim), so clearing
///   is the client's job — a finished programme must not
///   offer to "continue" into its last seconds.
/// - Any other stop reports the position the viewer stopped
///   at, exactly: it is the player's own presentation
///   position, not a served-bytes estimate, so no read-ahead
///   correction is applied on this side. (The rewind on the
///   reading side, plan 98's resumeRewind, stays — as a
///   context rewind; see titles_screen.)
library;

/// The position to report when a recorded viewing ends, or
/// null when nothing is to be reported.
///
/// [started] is whether playback ever reached the playing
/// state; [completed] is the player's end-of-stream signal;
/// [position] is the last position the player reported.
Duration? resumePositionToReport({
  required bool started,
  required bool completed,
  required Duration position,
}) {
  if (!started) return null;
  if (completed) return Duration.zero;
  return position.isNegative ? Duration.zero : position;
}
