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
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app/providers.dart';
import '../core/core.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.title, required this.session});

  /// Display heading: a recording's title, or a live channel's
  /// name (plan 39). The screen itself is source-agnostic — it
  /// plays the session's stream, finite or endless.
  final String title;
  final PlaybackSession session;

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

  /// How long playback may take to reach the playing state before
  /// the screen gives up with a timeout error (plan 29). Kept
  /// above mpv's network timeout (plan 30) so mpv's own classified
  /// error normally surfaces first and this stays a backstop.
  static const Duration startTimeout = Duration(seconds: 45);

  /// mpv's network timeout, set before opening (plan 30). The
  /// factory default of 5 s is shorter than a slow path's time to
  /// first byte even with the streaming proxy.
  static const int mpvNetworkTimeoutSeconds = 30;

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
        if (playing) {
          _playing = true;
          _watchdog?.cancel();
        }
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        _diag(DiagCategory.playback, 'player: buffering=$buffering');
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((error) {
        _diag(DiagCategory.playback, 'player: error: $error');
        _wakelockSession.setPlaying(false);
        _watchdog?.cancel();
        if (mounted && _error == null) {
          setState(() => _error = error);
        }
      }),
    );
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
      }
      await _player.open(Media(widget.session.mediaUri.toString()));
      _diag(DiagCategory.playback, 'player: open completed');
    } catch (e) {
      _diag(DiagCategory.playback, 'player: open failed: $e');
      _watchdog?.cancel();
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
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
      appBar: AppBar(title: Text(widget.title)),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '再生を開始できませんでした。\n$_error',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Video(controller: _videoController),
    );
  }
}
