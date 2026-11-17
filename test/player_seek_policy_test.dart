/// Tests for the player seek policy (player UI follow-up
/// after 1.4.0): the skip buttons act only on a definite
/// "yes" from mpv's seekable property, and the skip target
/// clamps to the stream's start and, when known, its end.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_seek_policy.dart';

void main() {
  group('isSeekablePropertyValue', () {
    test('only a definite yes is seekable', () {
      expect(isSeekablePropertyValue('yes'), isTrue);
    });

    test('no, empty and unknown values are not seekable', () {
      expect(isSeekablePropertyValue('no'), isFalse);
      expect(isSeekablePropertyValue(''), isFalse);
      expect(isSeekablePropertyValue(null), isFalse);
      expect(isSeekablePropertyValue('partially-seekable'), isFalse);
    });
  });

  group('skipSeekTarget', () {
    const duration = Duration(minutes: 30);

    test('forward skip lands ten seconds ahead', () {
      expect(
        skipSeekTarget(
          position: const Duration(minutes: 5),
          offset: skipSeekStep,
          duration: duration,
        ),
        const Duration(minutes: 5, seconds: 10),
      );
    });

    test('backward skip lands ten seconds back', () {
      expect(
        skipSeekTarget(
          position: const Duration(minutes: 5),
          offset: -skipSeekStep,
          duration: duration,
        ),
        const Duration(minutes: 4, seconds: 50),
      );
    });

    test('backward skip clamps at zero', () {
      expect(
        skipSeekTarget(
          position: const Duration(seconds: 4),
          offset: -skipSeekStep,
          duration: duration,
        ),
        Duration.zero,
      );
    });

    test('forward skip clamps at the duration', () {
      expect(
        skipSeekTarget(
          position: const Duration(minutes: 29, seconds: 55),
          offset: skipSeekStep,
          duration: duration,
        ),
        duration,
      );
    });

    test('an unknown duration clamps only at zero', () {
      expect(
        skipSeekTarget(
          position: const Duration(minutes: 5),
          offset: skipSeekStep,
          duration: Duration.zero,
        ),
        const Duration(minutes: 5, seconds: 10),
      );
      expect(
        skipSeekTarget(
          position: const Duration(seconds: 4),
          offset: -skipSeekStep,
          duration: Duration.zero,
        ),
        Duration.zero,
      );
    });
  });
}
