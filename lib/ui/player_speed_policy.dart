/// Playback speed policy (plan 86, plan 85 item 7): the rates
/// the player screen offers for recorded playback, and how
/// they are labelled.
///
/// The official torne mobile offers fast playback with audio
/// at 1.5–2x (plan 85.4, sourced); this app had no speed
/// control at all. mpv changes speed through its rate setting
/// (media_kit's setRate) and pitch-corrects the audio, so no
/// stream-side work is needed: the proxy serves the same
/// bytes and the demuxer simply consumes them faster.
///
/// The offered rates are 1.0 / 1.25 / 1.5 / 2.0: 1.5 and 2.0
/// cover the official range, 1.25 is the small step viewers
/// use for speech-heavy programmes, and 1.0 is the way back.
/// Rates above 2.0 trade away the audio's intelligibility
/// and are not offered.
///
/// Live viewing gets no speed control: a live stream has no
/// reservoir to catch up from, so a rate above 1.0 only makes
/// mpv chase the live edge and stall against the proxy. The
/// control is a recorded-playback feature, like the official
/// one.
library;

/// The playback rates the player screen offers, ascending.
/// Always contains 1.0 (normal speed).
const List<double> playbackSpeeds = [1.0, 1.25, 1.5, 2.0];

/// Whether the speed control is offered at all: recorded
/// playback only. A live stream cannot be fast-forwarded
/// (see the library comment).
bool canChangePlaybackSpeed({required bool live}) => !live;

/// The user-facing label for [rate]: '1倍', '1.25倍',
/// '1.5倍', '2倍'. Trailing zeros are dropped so the menu
/// reads the way a viewer expects.
String playbackSpeedLabel(double rate) {
  var text = rate.toStringAsFixed(2);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text倍';
}
