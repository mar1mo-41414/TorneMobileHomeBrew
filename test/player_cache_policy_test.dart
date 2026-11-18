/// Tests for the mpv cache policy (plan 80): recordings run
/// with mpv's cache on so the demuxer's re-reads stay local
/// (plan 78.1); live keeps it off (plan 54).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_cache_policy.dart';

void main() {
  group('mpvCacheMode', () {
    test('recorded playback uses the mpv cache', () {
      expect(mpvCacheMode(live: false), 'yes');
    });

    test('live playback keeps the cache off (plan 54)', () {
      expect(mpvCacheMode(live: true), 'no');
    });
  });

  group('recording demuxer cache sizes', () {
    test('the forward cache covers the probe re-reads', () {
      expect(recordingDemuxerMaxBytes, 32 * 1024 * 1024);
    });

    test('the back cache is the smaller half', () {
      expect(recordingDemuxerMaxBackBytes, 16 * 1024 * 1024);
      expect(
        recordingDemuxerMaxBackBytes,
        lessThan(recordingDemuxerMaxBytes),
      );
    });
  });
}
