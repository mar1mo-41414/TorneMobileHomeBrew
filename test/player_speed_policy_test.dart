/// Playback speed policy tests (plan 86, plan 85 item 7).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_speed_policy.dart';

void main() {
  group('playbackSpeeds', () {
    test('contains normal speed and is ascending', () {
      expect(playbackSpeeds, contains(1.0));
      final sorted = [...playbackSpeeds]..sort();
      expect(playbackSpeeds, sorted);
    });

    test('covers the official fast-playback range within 2x', () {
      expect(playbackSpeeds, containsAll(<double>[1.5, 2.0]));
      expect(playbackSpeeds.every((r) => r > 0 && r <= 2.0), isTrue);
    });
  });

  group('canChangePlaybackSpeed', () {
    test('recordings yes, live no', () {
      expect(canChangePlaybackSpeed(live: false), isTrue);
      expect(canChangePlaybackSpeed(live: true), isFalse);
    });
  });

  group('playbackSpeedLabel', () {
    test('drops trailing zeros', () {
      expect(playbackSpeedLabel(1.0), '1倍');
      expect(playbackSpeedLabel(2.0), '2倍');
      expect(playbackSpeedLabel(1.5), '1.5倍');
      expect(playbackSpeedLabel(1.25), '1.25倍');
    });
  });
}
