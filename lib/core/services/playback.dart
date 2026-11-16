/// The v1 PlaybackEngine: a stub that reports "unsupported"
/// (plan 1.2 item 5, 5.7). The UI turns this into the
/// "playback is not implemented yet" notice.
library;

import '../errors.dart';
import '../models/title.dart';
import 'interfaces.dart';

class UnsupportedPlaybackEngine implements PlaybackEngine {
  const UnsupportedPlaybackEngine();

  @override
  bool get isSupported => false;

  @override
  Future<void> startPlayback(RecordedTitle title, TitleRes res) {
    throw NasneError.unsupported(
      'playback:startPlayback',
      detail: 'DTCP-IP playback is not implemented in v1',
    );
  }
}
