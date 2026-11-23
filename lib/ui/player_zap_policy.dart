/// Channel zapping policy (owner request, 2026-11-23):
/// moving between live channels without leaving the player.
///
/// The official torne mobile changes channels while watching;
/// this app originally sent the viewer back to the channel
/// list to pick another one. The player now carries the
/// band's channels (see PlayerScreen.zapTargets) and moves
/// within them:
///
/// - The header shows the previous channel on the left, the
///   current channel in the centre and the next channel on
///   the right; tapping a side moves to that channel.
/// - The up / down keys move as well (desktop).
/// - The ends wrap: the channel after the last one is the
///   first, so zapping can circle the whole band.
///
/// Movement is live viewing only, and only with at least
/// two channels: a recording has no neighbouring channel,
/// and a one-channel band has nowhere to move to.
///
/// Switching itself follows the playback boundary: stop the
/// old session, start the new channel's session, open it on
/// the same player (see PlaybackEngine.startLivePlayback).
library;

/// Whether the player offers channel movement at all: live
/// viewing with at least two zap targets.
bool canZap({required bool live, required int targetCount}) =>
    live && targetCount > 1;

/// The index [delta] steps from [current] in a list of
/// [count] targets, wrapping at both ends. A non-positive
/// [count] keeps [current], so a degenerate list never
/// moves; callers gate on [canZap] before offering movement
/// at all.
int zapIndexAfter({
  required int current,
  required int delta,
  required int count,
}) {
  if (count <= 0) return current;
  return (current + delta) % count;
}
