/// Playback screen (Phase 5, plan 26): plays the decrypted TS
/// stream from the DTCP-IP session's loopback proxy via media_kit
/// (mpv). AVPlayer cannot decode MPEG-2 TS on iOS, hence media_kit.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/core.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.title, required this.session});

  final RecordedTitle title;
  final PlaybackSession session;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _open();
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(widget.session.mediaUri.toString()));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    widget.session.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title.title)),
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
