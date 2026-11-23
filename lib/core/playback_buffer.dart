/// Playback buffer setting (plan 126): how much decrypted
/// content the playback path banks ahead of the play position,
/// so a network gap shorter than the banked amount does not
/// stall playback. The motivating environment is an unstable
/// link (in-car use over a tethering / VPN path), where the
/// fetch side can run ahead at full link speed while the link
/// is good and coast through the bad patches.
///
/// The playback path has two banking layers:
///
/// - The DTCP proxy, which faces the network: in non-seekable
///   mode (live viewing and the unseekable fallback) a prefetch
///   queue capped by DtcpProxy.prefetchCapBytes, in seekable
///   mode (recordings) a window cache capped by
///   DtcpProxy.windowCapBytes. The producer / pump fills the
///   bank at link speed, independent of the player's reads.
/// - mpv's demuxer cache on the player side (recordings only;
///   live keeps the cache off — plan 54 measured the demuxer
///   cache stalling audio track switching on the unseekable
///   live stream, and this setting does not touch that).
///
/// The setting is expressed in seconds because that is the
/// unit a viewer can reason about ("how long a dropout can
/// be"). Seconds convert to bytes at [playbackBufferBytesPerSecond],
/// the fattest stream the app plays (a BS recording at DR
/// quality), so a choice banks AT LEAST that many seconds at
/// any lower bitrate — terrestrial DR, the mobile transcode —
/// and exactly that many at the fattest.
///
/// [playbackBufferStandardSeconds] (the default) is not a
/// byte amount at all: it selects the per-layer caps the app
/// has always run with (the proxy's two constants and the
/// player cache policy's demuxer limit), so the default
/// reproduces the hardware-verified behaviour byte for byte.
/// Any other choice sets one unified cap — the chosen seconds
/// at the reference rate — on the proxy's prefetch queue, the
/// proxy's window cache and mpv's demuxer-max-bytes alike.
/// mpv's demuxer-max-BACK-bytes is not scaled: it serves the
/// demuxer's backward scans and short step-backs (plan 78),
/// which have nothing to do with link stalls.
///
/// Memory: a non-standard choice can hold up to its byte cap
/// of plaintext in the proxy alone (120 s = 360 MiB), plus
/// the player's own cache on recordings. That is the trade
/// the viewer makes explicitly; the default stays at the
/// long-standing footprint.
///
/// Live viewing note: a live stream arrives in real time, so
/// its bank can only ever hold what accumulated between the
/// proxy starting and the player draining (plus any pause).
/// The setting raises the live queue's cap on the same terms
/// as the other layers — consistent and harmless — but the
/// effective live buffer stays bounded by real-time delivery;
/// the setting's real effect is on recorded playback.
library;

/// The setting value that keeps every layer's long-standing
/// cap: "standard". Also the default when nothing is stored.
const int playbackBufferStandardSeconds = 0;

/// The selectable buffer amounts, in seconds, standard first.
/// The settings screen renders one segment per entry.
const List<int> playbackBufferChoicesSeconds = <int>[
  playbackBufferStandardSeconds,
  30,
  60,
  120,
];

/// Bytes banked per chosen second: 3 MiB/s, just over the
/// 24 Mbps of the fattest broadcast stream (BS at DR), so a
/// choice never banks less than its seconds (see the library
/// comment).
const int playbackBufferBytesPerSecond = 3 * 1024 * 1024;

/// Normalizes an arbitrary integer to a selectable choice:
/// anything not in [playbackBufferChoicesSeconds] becomes
/// the standard value. A stored value the current build does
/// not know (written by a newer build, or corrupted) must
/// fall back to the verified default, never to an unreviewed
/// byte cap.
int normalizePlaybackBufferSeconds(int seconds) =>
    playbackBufferChoicesSeconds.contains(seconds)
    ? seconds
    : playbackBufferStandardSeconds;

/// Parses the stored form of the setting (a decimal integer
/// of seconds, as written by the settings notifier). Null,
/// unparsable and unknown values all read as the standard
/// value, per [normalizePlaybackBufferSeconds].
int parsePlaybackBufferSeconds(String? raw) {
  if (raw == null) return playbackBufferStandardSeconds;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null) return playbackBufferStandardSeconds;
  return normalizePlaybackBufferSeconds(parsed);
}

/// The byte cap a choice puts on each banking layer, or null
/// for the standard value — null meaning "the layer's own
/// long-standing default applies", which is what keeps the
/// standard choice byte-identical to the behaviour before
/// this setting existed.
int? playbackBufferCapBytes(int seconds) {
  final normalized = normalizePlaybackBufferSeconds(seconds);
  if (normalized == playbackBufferStandardSeconds) return null;
  return normalized * playbackBufferBytesPerSecond;
}
