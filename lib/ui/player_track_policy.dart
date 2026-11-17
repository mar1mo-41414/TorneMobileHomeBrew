/// Player track policy (plan 53): which track controls the
/// player screen offers, and how the selections resolve.
///
/// Measured basis (2026-11-17; partial DTCP-IP captures probed
/// with ffprobe and mpv 0.37 — see plan 53 for the full table):
/// every stream kind the app plays — recorded DR, recorded x3,
/// recorded mobile, live DR, live mobile — carries the ARIB
/// caption as ONE separate subtitle track (codec arib_caption),
/// never burned into the video, so captions are switched purely
/// by mpv's subtitle track selection. Dual-audio programmes
/// carry their second audio as a SECOND AAC track (observed on
/// a live NHK broadcast and on an x3 educational recording);
/// the single-track dual-mono form was not observed in the
/// owner's environment, and this policy covers only the
/// separate-track form that was measured.
///
/// The bundled mpv builds contain the caption support: the
/// Android libmpv.so and the iOS Mpv.framework inside the
/// shipped 1.3.0 binaries both carry the arib_caption decoder
/// and the S_ARIBSUB renderer.
///
/// mpv may auto-select a subtitle track matching the device
/// language — captions were seen rendered without any user
/// action on a Japanese Android phone in the field — so
/// "subtitles default to off" cannot be left to mpv's
/// defaults. The player screen forces the no-track selection
/// until the user turns captions on (see player_screen).
library;

/// Whether the subtitle toggle should be offered: the stream
/// carries at least one subtitle track.
bool canToggleSubtitles(int subtitleTrackCount) => subtitleTrackCount > 0;

/// Whether the audio switcher should be offered: the stream
/// carries two or more audio tracks (a main and a sub audio
/// component, as in dual-audio broadcasts).
bool canSwitchAudio(int audioTrackCount) => audioTrackCount >= 2;

/// Display label for the audio track at [index] in demuxer
/// order. By broadcast convention the first audio component is
/// the main audio and the second is the sub audio; anything
/// beyond that (not observed in practice) falls back to a
/// numbered label.
String audioTrackLabel(int index) => switch (index) {
  0 => '主音声',
  1 => '副音声',
  _ => '音声${index + 1}',
};

/// The subtitle track id to select for the current toggle
/// state: the first subtitle track when captions are on, and
/// null — mpv's "no track" — when they are off or the stream
/// carries none.
String? subtitleTrackIdToSelect({
  required bool subtitlesOn,
  required List<String> subtitleTrackIds,
}) => subtitlesOn && subtitleTrackIds.isNotEmpty ? subtitleTrackIds.first : null;

/// Index of the audio track with [selectedId] within
/// [trackIds], for the switcher's current-value display.
/// Falls back to 0 — the demuxer's first track, which is what
/// mpv selects by default — when the selection is unknown
/// ('auto' before playback settles) or not in the list.
int selectedAudioIndex({
  required String? selectedId,
  required List<String> trackIds,
}) {
  if (selectedId == null) return 0;
  final index = trackIds.indexOf(selectedId);
  return index >= 0 ? index : 0;
}
