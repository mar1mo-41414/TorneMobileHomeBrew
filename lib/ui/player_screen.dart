/// Playback screen (Phase 5, plan 26): plays the decrypted TS
/// stream from the DTCP-IP session's loopback proxy via media_kit
/// (mpv). AVPlayer cannot decode MPEG-2 TS on iOS, hence media_kit.
///
/// Plan 29: the player's state streams are mirrored into the
/// playback diagnostics category (playing / buffering transitions
/// and mpv errors), mpv errors are surfaced on screen instead of
/// an eternal spinner, and a start watchdog turns "nothing ever
/// plays" into a classified timeout error.
///
/// Plan 30: mpv's network timeout is raised from its 5 s default
/// to 30 s before opening. In the build-8 field test the player
/// failed with "Failed to open" about 5 s after the content GET
/// while the (then packet-at-a-time) proxy had not delivered a
/// single byte yet; the proxy now streams and prefetches, and the
/// longer timeout keeps a slow path from tripping mpv first.
///
/// Plan 32: while the player reports playing, a wakelock keeps
/// the device from idle-sleeping (the build-10 iPad field test
/// had the device try to sleep about five minutes into playback).
/// The lock follows the playing stream exactly and is released
/// on pause, stop, error and when this screen is disposed.
///
/// Plan 35: the screen no longer owns a private controller — it
/// opens a session on the app-wide [PlaybackWakelock], so two
/// overlapping player screens cannot drop the OS lock from under
/// each other (build-13 field log).
///
/// Plan 39: live viewing reuses this screen unchanged. Nothing
/// here seeks, resumes, or assumes a stream length (recordings
/// also arrive as an unbounded chunked stream), so an endless
/// broadcast needs no special case; leaving the screen stops
/// the session in dispose, which is what a channel switch is.
/// The wakelock follows the playing stream exactly as it does
/// for recordings.
///
/// Plan 42: for live viewing, mpv's "Cannot seek in this
/// stream." complaint no longer fails the start. mpv queues an
/// initial seek for streams whose timestamps do not start at
/// zero (observed with DR broadcasts on Android) and reports
/// the refusal at error level even though playback itself is
/// unaffected; the live stream is unseekable by design, so the
/// complaint is logged and ignored (see player_error_policy).
/// Recorded playback keeps the previous behaviour.
///
/// Plan 53: subtitle (caption) and sub-audio controls. Every
/// stream kind carries its ARIB caption as a separate subtitle
/// track (measured; see player_track_policy), so the caption
/// toggle is mpv's subtitle track selection — and because mpv
/// may auto-select a caption track matching the device
/// language, the default-off state is forced (sid=no before
/// open, re-applied when the track list settles) until the
/// user turns captions on. Dual-audio programmes carry a
/// second audio track; when two or more audio tracks exist an
/// audio switcher （主音声 / 副音声） is offered. Both selections
/// live only in this screen's state — like the quality choice,
/// nothing is persisted.
///
/// Plan 54 corrections, driven by the owner's build-20 device
/// log and desktop-mpv measurements on the same streams:
/// (1) media_kit's synthetic 'auto'/'no' list entries are no
/// longer counted as tracks — plan 53's menu sent "副音声" on
/// a single-audio stream to aid=no (silence). Real tracks
/// only; see player_track_policy.
/// (2) mpv's demuxer cache stalls audio track switching on
/// unseekable streams indefinitely (measured: still no audio
/// decode 30 s after a switch; the same switch from a file
/// settles in ~0.15 s, and with cache=no in ~2 s), so the
/// player disables mpv's cache before open. Jitter buffering
/// is the proxy prefetch queue's job, not mpv's cache.
/// (3) The caption toggle's selection is correct, but the
/// bundled ffmpeg builds carry no ARIB caption decoder
/// (plan 54; see player_track_policy), so captions cannot
/// render until the libmpv builds gain one.
///
/// Plan 86: a recording can open at the resume position the
/// nasne holds for it ([PlayerScreen.initialStart]); the title
/// detail asks whether to continue from there or start over.
/// Before this the position was fetched and displayed but never
/// used, so every viewing of a long programme restarted at the
/// beginning (plan 85 item 1).
///
/// Plan 102: the other half of that pair — leaving this screen
/// reports where the viewing stopped ([PlayerScreen
/// .onResumePosition]), because the unit does not learn a
/// position from being streamed to: its points stayed zero
/// through every HB playback until this write existed, so
/// "continue" could never be offered for them. The terms of
/// the report (nothing when playback never started, zero —
/// a cleared point — when it ran to the end) are
/// player_resume_policy's.
///
/// Plan 86 (plan 85 item 7): recorded playback gains a speed
/// control in the app bar (1.0 / 1.25 / 1.5 / 2.0, applied via
/// mpv's rate with pitch-corrected audio). Live viewing is
/// excluded — a live stream has nothing to catch up from
/// (see player_speed_policy).
///
/// Plan 86 (plan 85 item 9): the start-failure view leads
/// with a plain explanation and what to do next; the raw
/// player error moves into a collapsed detail section,
/// matching the playback error dialog (playback_launcher).
///
/// Plan 80: the seek-freeze fixes. Recorded playback now
/// runs with mpv's cache on (see player_cache_policy) so
/// the demuxer's re-reads stop round-tripping the proxy.
/// And a playback that had started and then dies mid-stream
/// — a fatal error after the start, or the silent stall of
/// plan 78, where mpv stopped on the last frame with no
/// error at all — is surfaced as an interruption over the
/// frozen frame, with a resume action that re-opens the
/// same session stream in place, instead of the screen
/// failing wholesale as if the start had been bad.
///
/// Player UI follow-up (after 1.4.0), from the owner's
/// device feedback: the recorded screen's transport row
/// gains ±10 s skip buttons, and the seek bar gains a
/// taller touch target. The buttons follow mpv's own
/// `seekable` property and stay disabled while the stream
/// is not seekable — with the loopback proxy's chunked,
/// range-less responses that is today's steady state (see
/// player_seek_policy). The seek bar's stock Material
/// theme leaves it flush with the bottom edge outside
/// fullscreen (zero margin, and the controls take no
/// safe-area padding there), under the iPhone home
/// indicator where a thumb cannot reach it; the themes
/// below raise its container height and thumb size and
/// lift the non-fullscreen bar off the edge.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/providers.dart';
import '../core/core.dart';
import 'player_cache_policy.dart';
import 'player_error_policy.dart';
import 'player_resume_policy.dart';
import 'player_seek_policy.dart';
import 'player_speed_policy.dart';
import 'player_track_policy.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.session,
    this.live = false,
    this.initialStart,
    this.onResumePosition,
  });

  /// Display heading: a recording's title, or a live channel's
  /// name (plan 39). The screen itself is source-agnostic — it
  /// plays the session's stream, finite or endless.
  final String title;
  final PlaybackSession session;

  /// Whether the session is a live broadcast (plan 43). A live
  /// stream is unseekable by design, so mpv's seek complaint is
  /// non-fatal there (see player_error_policy).
  final bool live;

  /// Where a recording starts playing (plan 86): the resume
  /// position the nasne recorded for the title, when the viewer
  /// chose to continue from it. Null (and always null for live)
  /// starts at the beginning. Handed to mpv as the open start,
  /// so the proxy's time-seek path establishes the stream at
  /// that position from the first byte.
  final Duration? initialStart;

  /// Where the position a recording was stopped at goes when
  /// this screen closes (plan 102): the unit is told, so its
  /// resume point — the value [initialStart] is later read
  /// from — follows the viewer. What is sent follows
  /// player_resume_policy: the stopped-at position, or zero
  /// (clearing the point) when playback ran to the end, and
  /// nothing at all when playback never started. Null (live
  /// viewing has no position to report) disables the report.
  ///
  /// The report is a notification to the unit, not local
  /// persistence: it is awaited inside its own task off the
  /// dispose path, and a failure is logged to the playback
  /// diagnostics and dropped — leaving the player must never
  /// fail or hang because a report did not land.
  final Future<void> Function(Duration position)? onResumePosition;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  late final WakelockSession _wakelockSession;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _watchdog;
  bool _playing = false;
  String? _error;

  /// Interruption state (plan 80): playback that had started
  /// stopped mid-stream — a fatal player error after the
  /// start, or the silent stall of plan 78 — and the notice
  /// with its resume action is showing over the frozen frame.
  bool _interrupted = false;
  String? _interruptDetail;
  Timer? _stallTimer;

  /// The latest value of the playing stream (unlike
  /// [_playing], which latches once playback has started),
  /// and the signals the interruption policy reads: mpv's
  /// end-of-stream flag, whether buffering was the last
  /// observed state while playing, and the last position a
  /// resume should return to.
  bool _playingNow = false;
  bool _completed = false;
  bool _bufferingSincePlaying = false;
  Duration _lastPosition = Duration.zero;

  /// How long a mid-stream stop may last before it is
  /// surfaced as an interruption (plan 80): long enough for
  /// mpv's own recovery and a passing stall, short enough
  /// that a dead playback does not sit silent.
  static const Duration stallTimeout = Duration(seconds: 10);

  /// Tracks the demuxer currently reports, and the selection
  /// mpv currently holds (plan 53). Both start empty/'auto'
  /// and settle once the stream is being demuxed.
  Tracks _tracks = const Tracks();
  Track _selectedTrack = const Track();

  /// The demuxer's real audio tracks, without media_kit's
  /// synthetic 'auto'/'no' entries (plan 54).
  List<AudioTrack> get _realAudioTracks => [
    for (final track in _tracks.audio)
      if (isRealTrackId(track.id)) track,
  ];

  /// The demuxer's real subtitle tracks (plan 54).
  List<SubtitleTrack> get _realSubtitleTracks => [
    for (final track in _tracks.subtitle)
      if (isRealTrackId(track.id)) track,
  ];

  /// The caption toggle (plan 53). Default off, per the
  /// owner's spec; kept in this state only, never persisted.
  bool _subtitlesOn = false;

  /// The playback rate (plan 86, plan 85 item 7): 1.0 is
  /// normal speed. Offered for recordings only (see
  /// player_speed_policy); kept in this state only, like the
  /// caption and audio selections, and never persisted. mpv
  /// holds the rate on the player instance, so it carries
  /// over the in-place resume's re-open (plan 80) unchanged.
  double _playbackRate = 1.0;

  /// Whether mpv reports the current stream seekable,
  /// observed from its `seekable` property (player UI
  /// follow-up). Starts false — the skip buttons stay
  /// disabled until mpv gives a definite yes — and follows
  /// the property for the screen's lifetime. The buttons
  /// listen to this notifier directly, so no rebuild of
  /// this screen is involved when it flips. The property
  /// observation is registered on the player instance and
  /// dies with it; the notifier itself holds nothing that
  /// needs releasing.
  final ValueNotifier<bool> _seekable = ValueNotifier<bool>(false);

  /// How long playback may take to reach the playing state before
  /// the screen gives up with a timeout error (plan 29). Kept
  /// above mpv's network timeout (plan 30) so mpv's own classified
  /// error normally surfaces first and this stays a backstop.
  static const Duration startTimeout = Duration(seconds: 45);

  /// mpv's network timeout, set before opening (plan 30). The
  /// factory default of 5 s is shorter than a slow path's time to
  /// first byte even with the streaming proxy.
  static const int mpvNetworkTimeoutSeconds = 30;

  /// Seek bar dimensions in the video controls (player UI
  /// follow-up). The stock Material theme's visible bar is
  /// 2.4 px inside a 36 px container with a 12.8 px thumb;
  /// the container is the touch target, so it grows to
  /// 48 px, the thumb to 16 px and the visible bar to 4 px.
  /// The desktop theme takes the same three values.
  static const double seekBarThickness = 4.0;
  static const double seekBarTouchHeight = 48.0;
  static const double seekBarThumbDiameter = 16.0;

  /// How far the non-fullscreen seek bar is lifted off the
  /// video's bottom edge (player UI follow-up). Outside
  /// fullscreen the stock theme gives the bar a zero margin
  /// and the controls no safe-area padding, leaving it
  /// under the iPhone home indicator; the fullscreen theme
  /// already carries a 42 px margin over the safe-area
  /// padding and keeps it.
  static const double seekBarBottomLift = 12.0;

  DiagLog get _diag => ref.read(diagLogProvider);

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _wakelockSession = ref.read(playbackWakelockProvider).openSession();
    _watchdog = Timer(startTimeout, _onStartTimeout);
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        _diag(DiagCategory.playback, 'player: playing=$playing');
        _wakelockSession.setPlaying(playing);
        final wasPlaying = _playingNow;
        _playingNow = playing;
        if (playing) {
          _playing = true;
          _watchdog?.cancel();
          // A (re)start clears any interruption state
          // (plan 80): playback is running again, whether it
          // recovered on its own or the user resumed it.
          _stallTimer?.cancel();
          _bufferingSincePlaying = false;
          if (_interrupted && mounted) {
            setState(() {
              _interrupted = false;
              _interruptDetail = null;
            });
          }
        } else if (wasPlaying) {
          _onPlaybackStopped();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        _diag(DiagCategory.playback, 'player: buffering=$buffering');
        if (_playingNow) {
          // Buffering while mpv is trying to play is the
          // signature the plan-78 stalls left just before
          // mpv stopped (plan 80); buffering clearing again
          // while playing is a recovery and clears it.
          _bufferingSincePlaying = buffering;
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        _diag(DiagCategory.playback, 'player: completed=$completed');
        _completed = completed;
      }),
    );
    _subscriptions.add(
      _player.stream.position.listen((position) {
        _lastPosition = position;
      }),
    );
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        _diag(
          DiagCategory.playback,
          'player: tracks: video=${tracks.video.length} '
          'audio=${tracks.audio.length} subtitle=${tracks.subtitle.length} '
          '(real audio='
          '${realTrackIds([for (final t in tracks.audio) t.id]).length} '
          'real subtitle='
          '${realTrackIds([for (final t in tracks.subtitle) t.id]).length})',
        );
        for (final track in tracks.audio) {
          _diag(
            DiagCategory.playback,
            'player: audio track: id=${track.id} codec=${track.codec} '
            'channels=${track.channelscount} language=${track.language}',
          );
        }
        for (final track in tracks.subtitle) {
          _diag(
            DiagCategory.playback,
            'player: subtitle track: id=${track.id} codec=${track.codec} '
            'language=${track.language}',
          );
        }
        if (mounted) setState(() => _tracks = tracks);
        // Re-resolve the caption selection against the settled
        // track list: applies the forced-off default, or the
        // track the user asked for before the list arrived.
        _applySubtitleSelection();
      }),
    );
    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (mounted) setState(() => _selectedTrack = track);
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((error) {
        _diag(DiagCategory.playback, 'player: error: $error');
        if (!playerErrorIsFatal(
          error,
          live: widget.live,
          alreadyPlaying: _playing,
        )) {
          // A seek complaint the policy classes as benign
          // (plan 43, extended after 1.4.0): live viewing,
          // where the stream is unseekable by design, or any
          // playback already under way, where the complaint
          // can only be answering a seek and mpv keeps
          // playing. Leave the watchdog running as the
          // arbiter of a start that never reaches playback.
          _diag(
            DiagCategory.playback,
            'player: ignoring the seek complaint '
            '(live=${widget.live}, alreadyPlaying=$_playing)',
          );
          return;
        }
        _wakelockSession.setPlaying(false);
        _watchdog?.cancel();
        if (!mounted) return;
        if (_playing) {
          // The failure arrived after playback had started
          // (plan 80): an interruption, not a failed start.
          // Keep the frozen frame and offer the in-place
          // resume instead of replacing the screen with the
          // start-failure message.
          setState(() {
            _interrupted = true;
            _interruptDetail = error;
          });
        } else if (_error == null) {
          setState(() => _error = error);
        }
      }),
    );
    _observeSeekable();
    _open();
  }

  void _onStartTimeout() {
    if (!mounted || _playing || _error != null) return;
    _diag(
      DiagCategory.playback,
      'player: no playback within ${startTimeout.inSeconds} seconds; '
      'showing a timeout error',
    );
    setState(
      () => _error =
          '再生が開始できませんでした (${startTimeout.inSeconds} 秒以内に'
          '映像が届きませんでした)。',
    );
  }

  /// A playing→stopped transition (plan 80): when the
  /// policy classes it as a mid-stream death, give mpv a
  /// grace period to recover on its own before surfacing
  /// anything.
  void _onPlaybackStopped() {
    if (!playbackStoppedEarly(
      alreadyPlaying: _playing,
      completed: _completed,
      bufferedBeforeStop: _bufferingSincePlaying,
    )) {
      return;
    }
    _diag(
      DiagCategory.playback,
      'player: playback stopped after buffering without '
      'completing; watching for a recovery for '
      '${stallTimeout.inSeconds} seconds (plan 80)',
    );
    _stallTimer?.cancel();
    _stallTimer = Timer(stallTimeout, _onStallTimeout);
  }

  void _onStallTimeout() {
    if (!mounted || _playingNow || _completed || _error != null) {
      return;
    }
    _diag(
      DiagCategory.playback,
      'player: playback did not recover; showing the '
      'interruption notice (plan 80)',
    );
    setState(() => _interrupted = true);
  }

  /// Re-establishes playback after an interruption, in
  /// place (plan 80): the session — authentication, the
  /// loopback proxy and all — is still alive (only leaving
  /// the screen stops it), so resuming re-opens the same
  /// stream URL on the same player and, for a recording,
  /// starts from the last observed position. The title is
  /// never re-opened from the list, and nothing is
  /// re-asked. The player's properties (cache mode, sid)
  /// persist across the re-open; the track listener
  /// re-applies the caption selection when the new track
  /// list settles, exactly as at the first open.
  Future<void> _resume() async {
    _diag(
      DiagCategory.playback,
      'player: resuming after an interruption at '
      '${_lastPosition.inSeconds}s (live=${widget.live})',
    );
    _stallTimer?.cancel();
    setState(() {
      _interrupted = false;
      _interruptDetail = null;
    });
    try {
      await _player.open(
        Media(
          widget.session.mediaUri.toString(),
          start: (!widget.live && _lastPosition > Duration.zero)
              ? _lastPosition
              : null,
        ),
      );
      _diag(DiagCategory.playback, 'player: resume open completed');
    } catch (e) {
      _diag(DiagCategory.playback, 'player: resume failed: $e');
      if (mounted) {
        setState(() {
          _interrupted = true;
          _interruptDetail = '$e';
        });
      }
    }
  }

  /// Applies the caption selection for the current toggle
  /// state (plan 53): the first caption track when on, and
  /// mpv's no-track selection when off — the off case is what
  /// keeps mpv's language-based auto-selection from turning
  /// captions on by itself.
  Future<void> _applySubtitleSelection() async {
    final id = subtitleTrackIdToSelect(
      subtitlesOn: _subtitlesOn,
      subtitleTrackIds: [for (final track in _realSubtitleTracks) track.id],
    );
    try {
      if (id == null) {
        await _player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        await _player.setSubtitleTrack(
          _realSubtitleTracks.firstWhere((track) => track.id == id),
        );
      }
    } catch (e) {
      _diag(DiagCategory.playback, 'player: subtitle selection failed: $e');
    }
  }

  void _toggleSubtitles() {
    setState(() => _subtitlesOn = !_subtitlesOn);
    _diag(
      DiagCategory.playback,
      'player: subtitles ${_subtitlesOn ? 'on' : 'off'} (user toggle)',
    );
    _applySubtitleSelection();
  }

  Future<void> _selectAudioTrack(int index) async {
    if (index < 0 || index >= _realAudioTracks.length) return;
    final track = _realAudioTracks[index];
    _diag(
      DiagCategory.playback,
      'player: audio track -> ${audioTrackLabel(index)} (id=${track.id})',
    );
    try {
      await _player.setAudioTrack(track);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: audio selection failed: $e');
    }
  }

  /// Applies a user-chosen playback rate (plan 86, plan 85
  /// item 7). mpv pitch-corrects the audio at these rates,
  /// so speech stays intelligible; the proxy and the stream
  /// are untouched — the demuxer just consumes faster.
  Future<void> _selectPlaybackRate(double rate) async {
    if (rate == _playbackRate) return;
    setState(() => _playbackRate = rate);
    _diag(
      DiagCategory.playback,
      'player: playback rate -> ${playbackSpeedLabel(rate)} '
      '(user selection)',
    );
    try {
      await _player.setRate(rate);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: rate change failed: $e');
    }
  }

  int get _selectedAudioIndex => selectedAudioIndex(
    selectedId: _selectedTrack.audio.id,
    trackIds: [for (final track in _realAudioTracks) track.id],
  );

  /// Follows mpv's `seekable` property into [_seekable]
  /// (player UI follow-up): the recorded screen's skip
  /// buttons' enable signal. mpv re-evaluates the property
  /// as the demuxer settles, so this is an observation,
  /// not a one-shot read.
  Future<void> _observeSeekable() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.observeProperty('seekable', (value) async {
        final seekable = isSeekablePropertyValue(value);
        if (seekable != _seekable.value) {
          _diag(
            DiagCategory.playback,
            'player: seekable=$value; skip buttons '
            '${seekable ? 'enabled' : 'disabled'}',
          );
          _seekable.value = seekable;
        }
      });
    } catch (e) {
      _diag(DiagCategory.playback, 'player: seekable observation failed: $e');
    }
  }

  /// Seeks by [offset] (±[skipSeekStep]) from the current
  /// position (player UI follow-up). Reached only through
  /// the skip buttons, which stay disabled while [_seekable]
  /// is false; a refusal that still comes back lands on the
  /// error stream and is classified there (see
  /// player_error_policy), so it cannot fail a playback
  /// already under way.
  Future<void> _skipSeek(Duration offset) async {
    final target = skipSeekTarget(
      position: _player.state.position,
      offset: offset,
      duration: _player.state.duration,
    );
    _diag(
      DiagCategory.playback,
      'player: skip seek by ${offset.inSeconds}s '
      'to ${target.inSeconds}s',
    );
    try {
      await _player.seek(target);
    } catch (e) {
      _diag(DiagCategory.playback, 'player: skip seek failed: $e');
    }
  }

  Future<void> _open() async {
    _diag(DiagCategory.playback, 'player: opening ${widget.session.mediaUri}');
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty(
          'network-timeout',
          '$mpvNetworkTimeoutSeconds',
        );
        _diag(
          DiagCategory.playback,
          'player: mpv network-timeout set to '
          '${mpvNetworkTimeoutSeconds}s',
        );
        // Captions default to off (plan 53): pin the subtitle
        // selection to "no track" before the stream opens, so
        // mpv's auto-selection never gets a say. The tracks
        // listener re-applies the resolution once the demuxer's
        // track list settles.
        await platform.setProperty('sid', 'no');
        _diag(DiagCategory.playback, 'player: mpv sid pinned to no (default)');
        // mpv's cache follows the playback kind (plans 54
        // and 80; see player_cache_policy). Live keeps it
        // off: with the demuxer cache on, an audio track
        // switch on the unseekable live stream never
        // re-engages decoding (measured 30 s and counting),
        // and the proxy's prefetch queue is the jitter
        // buffer. Recordings turn it on, sized by the two
        // demuxer limits, so the demuxer's probe and seek
        // re-reads (plan 78.1) are absorbed locally instead
        // of round-tripping the proxy per hop.
        final cacheMode = mpvCacheMode(live: widget.live);
        await platform.setProperty('cache', cacheMode);
        if (!widget.live) {
          await platform.setProperty(
            'demuxer-max-bytes',
            '$recordingDemuxerMaxBytes',
          );
          await platform.setProperty(
            'demuxer-max-back-bytes',
            '$recordingDemuxerMaxBackBytes',
          );
        }
        _diag(
          DiagCategory.playback,
          'player: mpv cache=$cacheMode (live=${widget.live})',
        );
      }
      final start =
          (!widget.live &&
              widget.initialStart != null &&
              widget.initialStart! > Duration.zero)
          ? widget.initialStart
          : null;
      if (start != null) {
        _diag(
          DiagCategory.playback,
          'player: opening at the resume position ${start.inSeconds}s '
          '(plan 86)',
        );
      }
      await _player.open(
        Media(widget.session.mediaUri.toString(), start: start),
      );
      _diag(DiagCategory.playback, 'player: open completed');
      await _applySubtitleSelection();
    } catch (e) {
      _diag(DiagCategory.playback, 'player: open failed: $e');
      if (!playerErrorIsFatal('$e', live: widget.live)) {
        // Same seek complaint as the error-stream path, thrown
        // through open() instead (plan 43): not a failed start.
        _diag(
          DiagCategory.playback,
          'player: ignoring the seek complaint for live viewing',
        );
        return;
      }
      _watchdog?.cancel();
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The Material (Android / iOS) controls theme with this
  /// screen's seek bar dimensions (player UI follow-up)
  /// and, for recordings, the ±10 s skip buttons in the
  /// transport row. Built from media_kit's defaults via
  /// copyWith so the gestures and the rest of the stock
  /// behaviour carry over unchanged.
  MaterialVideoControlsThemeData _materialControlsTheme({
    required bool fullscreen,
  }) {
    final base = fullscreen
        ? kDefaultMaterialVideoControlsThemeDataFullscreen
        : kDefaultMaterialVideoControlsThemeData;
    var data = base.copyWith(
      seekBarHeight: seekBarThickness,
      seekBarContainerHeight: seekBarTouchHeight,
      seekBarThumbSize: seekBarThumbDiameter,
    );
    if (!fullscreen) {
      data = data.copyWith(
        seekBarMargin: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: seekBarBottomLift,
        ),
      );
    }
    if (!widget.live) {
      data = data.copyWith(
        primaryButtonBar: _recordedPrimaryButtonBar(
          playIconSize: fullscreen ? 56.0 : 48.0,
        ),
      );
    }
    return data;
  }

  /// The desktop controls theme with the same seek bar
  /// dimensions (player UI follow-up); the desktop defaults
  /// are one data set for both normal and fullscreen. The
  /// skip buttons join the bottom transport row, which is
  /// where the desktop controls keep theirs.
  MaterialDesktopVideoControlsThemeData _desktopControlsTheme() {
    var data = kDefaultMaterialDesktopVideoControlsThemeData.copyWith(
      seekBarHeight: seekBarThickness,
      seekBarContainerHeight: seekBarTouchHeight,
      seekBarThumbSize: seekBarThumbDiameter,
    );
    if (!widget.live) {
      data = data.copyWith(bottomButtonBar: _recordedDesktopButtonBar());
    }
    return data;
  }

  /// The Material transport row for recordings: media_kit's
  /// stock row with a ±10 s skip button flanking the
  /// play/pause button on each side (player UI follow-up).
  List<Widget> _recordedPrimaryButtonBar({required double playIconSize}) => [
    const Spacer(flex: 2),
    const MaterialSkipPreviousButton(),
    const Spacer(),
    _SkipSeekButton(
      seekable: _seekable,
      offset: -skipSeekStep,
      onSkip: _skipSeek,
    ),
    const Spacer(),
    MaterialPlayOrPauseButton(iconSize: playIconSize),
    const Spacer(),
    _SkipSeekButton(
      seekable: _seekable,
      offset: skipSeekStep,
      onSkip: _skipSeek,
    ),
    const Spacer(),
    const MaterialSkipNextButton(),
    const Spacer(flex: 2),
  ];

  /// The desktop bottom row for recordings: the stock row
  /// with the ±10 s skip buttons after the skip-next button
  /// (player UI follow-up).
  List<Widget> _recordedDesktopButtonBar() => [
    const MaterialDesktopSkipPreviousButton(),
    const MaterialDesktopPlayOrPauseButton(),
    const MaterialDesktopSkipNextButton(),
    _SkipSeekButton(
      seekable: _seekable,
      offset: -skipSeekStep,
      onSkip: _skipSeek,
      iconSize: 28,
    ),
    _SkipSeekButton(
      seekable: _seekable,
      offset: skipSeekStep,
      onSkip: _skipSeek,
      iconSize: 28,
    ),
    const MaterialDesktopVolumeButton(),
    const MaterialDesktopPositionIndicator(),
    const Spacer(),
    const MaterialDesktopFullscreenButton(),
  ];

  /// Reports the stopped-at position to the unit as the
  /// screen closes (plan 102; the terms are
  /// player_resume_policy's). Runs off the dispose path: the
  /// report is awaited inside its own task, its failure is
  /// logged and dropped, and dispose never waits on it — the
  /// screen is leaving either way, and the session teardown
  /// below does not depend on the report landing.
  void _reportResumePosition() {
    final sink = widget.onResumePosition;
    if (sink == null) return;
    final position = resumePositionToReport(
      started: _playing,
      completed: _completed,
      position: _lastPosition,
    );
    if (position == null) return;
    final diag = _diag;
    diag(
      DiagCategory.playback,
      'player: reporting the resume position '
      '${position.inSeconds}s to the unit (plan 102)',
    );
    unawaited(
      sink(position).then(
        (_) {},
        onError: (Object e) {
          diag(
            DiagCategory.playback,
            'player: resume position report failed: $e',
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _reportResumePosition();
    _watchdog?.cancel();
    _stallTimer?.cancel();
    _wakelockSession.release();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    widget.session.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (canChangePlaybackSpeed(live: widget.live))
            PopupMenuButton<double>(
              tooltip: '再生速度',
              initialValue: _playbackRate,
              onSelected: _selectPlaybackRate,
              itemBuilder: (context) => [
                for (final rate in playbackSpeeds)
                  CheckedPopupMenuItem<double>(
                    value: rate,
                    checked: rate == _playbackRate,
                    child: Text(playbackSpeedLabel(rate)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed),
                    if (_playbackRate != 1.0) ...[
                      const SizedBox(width: 4),
                      Text(playbackSpeedLabel(_playbackRate)),
                    ],
                  ],
                ),
              ),
            ),
          if (canSwitchAudio(_realAudioTracks.length))
            PopupMenuButton<int>(
              tooltip: '音声',
              icon: const Icon(Icons.audiotrack),
              initialValue: _selectedAudioIndex,
              onSelected: _selectAudioTrack,
              itemBuilder: (context) => [
                for (var i = 0; i < _realAudioTracks.length; i++)
                  CheckedPopupMenuItem<int>(
                    value: i,
                    checked: i == _selectedAudioIndex,
                    child: Text(audioTrackLabel(i)),
                  ),
              ],
            ),
          if (canToggleSubtitles(_realSubtitleTracks.length))
            IconButton(
              tooltip: '字幕',
              icon: Icon(
                _subtitlesOn ? Icons.closed_caption : Icons.closed_caption_off,
              ),
              onPressed: _toggleSubtitles,
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('再生を開始できませんでした。', textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      const Text(
                        'nasne との接続やネットワークの状態を確認して、'
                        'もう一度お試しください。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      // The raw player error (an mpv message, or
                      // this screen's own timeout wording) is
                      // diagnostic text, not something a viewer
                      // can act on: it sits behind the detail
                      // expander (plan 86, plan 85 item 9), and
                      // is in the diagnostic log as well.
                      ExpansionTile(
                        title: const Text('詳細'),
                        children: [
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                MaterialVideoControlsTheme(
                  normal: _materialControlsTheme(fullscreen: false),
                  fullscreen: _materialControlsTheme(fullscreen: true),
                  child: MaterialDesktopVideoControlsTheme(
                    normal: _desktopControlsTheme(),
                    fullscreen: _desktopControlsTheme(),
                    child: Video(controller: _videoController),
                  ),
                ),
                if (_interrupted) _buildInterruptionBanner(),
              ],
            ),
    );
  }

  /// The interruption notice (plan 80): shown over the
  /// frozen frame when playback that had started dies
  /// mid-stream. Resume re-establishes the stream in place
  /// (see [_resume]); the close button dismisses the notice
  /// and leaves the stopped frame as it is.
  Widget _buildInterruptionBanner() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        color: Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '再生が中断されました',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_interruptDetail != null)
                    Text(
                      _interruptDetail!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: _resume, child: const Text('再開')),
            IconButton(
              tooltip: '閉じる',
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _interrupted = false),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ±10-second skip button for the video controls' button
/// bars (player UI follow-up). Follows the seekable signal
/// the player screen observes from mpv: enabled — and white,
/// like the neighbouring transport buttons — while the
/// stream is seekable, and a disabled, dimmed button while
/// it is not, so an unseekable stream shows its state
/// instead of inviting a seek that would be refused.
class _SkipSeekButton extends StatelessWidget {
  const _SkipSeekButton({
    required this.seekable,
    required this.offset,
    required this.onSkip,
    this.iconSize = 36,
  });

  /// The observed seekable signal (see _PlayerScreenState).
  final ValueListenable<bool> seekable;

  /// How far this button seeks: −[skipSeekStep] or
  /// +[skipSeekStep]; the sign also picks the icon.
  final Duration offset;

  /// Invoked with [offset] when the button is tapped.
  final void Function(Duration offset) onSkip;

  /// Icon size: 36 in the Material transport row, matching
  /// its larger centre buttons; the desktop row passes its
  /// own 28.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final forward = offset > Duration.zero;
    return ValueListenableBuilder<bool>(
      valueListenable: seekable,
      builder: (context, canSeek, _) => IconButton(
        tooltip: forward ? '10秒スキップ' : '10秒戻し',
        iconSize: iconSize,
        color: Colors.white,
        onPressed: canSeek ? () => onSkip(offset) : null,
        icon: Icon(forward ? Icons.forward_10 : Icons.replay_10),
      ),
    );
  }
}
