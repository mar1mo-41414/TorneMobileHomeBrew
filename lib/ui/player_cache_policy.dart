/// Which mpv cache mode a playback kind runs with (plan 80).
///
/// Recorded playback runs with mpv's cache ON. The
/// seek-freeze chain measured in plan 78.1 was the demuxer
/// re-reading the stream through the loopback proxy at every
/// step — head probe, tail probe, backward scans, seek
/// refinement — each hop a fresh proxy round trip competing
/// with the playback stream itself. mpv's own cache, sized
/// by the demuxer-max-bytes options the player screen sets
/// alongside, absorbs those re-reads locally instead.
///
/// Live playback keeps the cache OFF (plan 54): on the
/// unseekable live stream the demuxer cache stalled audio
/// track switching indefinitely (measured), and an endless
/// broadcast has no tail to probe or past to re-read, so
/// nothing in plan 78 argues for changing the live side.
library;

import '../core/playback_buffer.dart';

/// mpv's `cache` option value for the playback kind: 'yes'
/// for recordings, 'no' for live (see the library comment).
String mpvCacheMode({required bool live}) => live ? 'no' : 'yes';

/// How much demuxer cache a recording may hold ahead of the
/// play position (mpv's `demuxer-max-bytes`). Sized to cover
/// the demuxer's probe and refinement re-reads around a
/// position (plan 78.1) without turning the player into a
/// second full copy of the window the proxy already keeps.
const int recordingDemuxerMaxBytes = 32 * 1024 * 1024;

/// The forward demuxer limit in force for a recording under
/// the viewer's playback buffer choice (plan 126): the
/// long-standing [recordingDemuxerMaxBytes] for the standard
/// choice, the choice's unified byte cap otherwise (see
/// core/playback_buffer.dart for the conversion and why the
/// demuxer layer follows the same cap as the proxy's banks).
int recordingDemuxerMaxBytesFor(int bufferSeconds) =>
    playbackBufferCapBytes(bufferSeconds) ?? recordingDemuxerMaxBytes;

/// How much demuxer cache a recording may hold behind the
/// play position (mpv's `demuxer-max-back-bytes`): the
/// demuxer's backward scans and a small step back stay
/// local instead of re-entering the proxy.
const int recordingDemuxerMaxBackBytes = 16 * 1024 * 1024;
