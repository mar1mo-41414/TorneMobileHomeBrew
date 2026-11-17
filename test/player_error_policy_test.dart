/// Tests for the player error policy (plan 43): mpv's
/// "Cannot seek in this stream." complaint is non-fatal for
/// live viewing (the stream is unseekable by design) and keeps
/// its previous fatal treatment for recorded playback.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_error_policy.dart';

void main() {
  group('isUnseekableStreamError', () {
    test('matches the exact mpv message', () {
      expect(isUnseekableStreamError('Cannot seek in this stream.'), isTrue);
    });

    test('matches the message with surrounding text', () {
      expect(
        isUnseekableStreamError('mpv error: Cannot seek in this stream.'),
        isTrue,
      );
    });

    test('matches the companion force-seekable hint (plan 56)', () {
      expect(
        isUnseekableStreamError(
          "You can force it with '--force-seekable=yes'.",
        ),
        isTrue,
      );
    });

    test('does not match other player errors', () {
      expect(isUnseekableStreamError('Failed to open.'), isFalse);
      expect(isUnseekableStreamError('Cannot open stream.'), isFalse);
      expect(isUnseekableStreamError(''), isFalse);
    });
  });

  group('playerErrorIsFatal', () {
    const seekError = 'Cannot seek in this stream.';

    test('the seek complaint is non-fatal for live viewing', () {
      expect(playerErrorIsFatal(seekError, live: true), isFalse);
    });

    test('the seek complaint stays fatal for recorded playback', () {
      expect(playerErrorIsFatal(seekError, live: false), isTrue);
    });

    test('the companion hint is non-fatal for live viewing (plan 56)', () {
      expect(
        playerErrorIsFatal(
          "You can force it with '--force-seekable=yes'.",
          live: true,
        ),
        isFalse,
      );
    });

    test('the companion hint stays fatal for recorded playback', () {
      expect(
        playerErrorIsFatal(
          "You can force it with '--force-seekable=yes'.",
          live: false,
        ),
        isTrue,
      );
    });

    test('other errors stay fatal for live viewing', () {
      expect(playerErrorIsFatal('Failed to open.', live: true), isTrue);
      expect(playerErrorIsFatal('network timeout', live: true), isTrue);
    });

    test('other errors stay fatal for recorded playback', () {
      expect(playerErrorIsFatal('Failed to open.', live: false), isTrue);
    });
  });
}
