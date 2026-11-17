/// The v1 PlaybackEngine stub: reports "unsupported" (plan 1.2
/// item 5, 5.7). Phase 5 adds the real DTCP-IP engine in
/// services/dtcp_playback.dart; this stub remains for configurations
/// without one (and for tests).
library;

import '../errors.dart';
import '../models/live_channel.dart';
import '../models/title.dart';
import 'interfaces.dart';

class UnsupportedPlaybackEngine implements PlaybackEngine {
  const UnsupportedPlaybackEngine();

  @override
  bool get isSupported => false;

  @override
  Future<PlaybackSession> startPlayback(RecordedTitle title, TitleRes res) {
    throw NasneError.unsupported(
      'playback:startPlayback',
      detail: 'DTCP-IP playback is not implemented in v1',
    );
  }

  @override
  Future<PlaybackSession> startLivePlayback(
    LiveChannel channel,
    TitleRes res,
  ) {
    throw NasneError.unsupported(
      'playback:startLivePlayback',
      detail: 'DTCP-IP live viewing is not implemented in v1',
    );
  }
}
