/// Tests for the player error policy (plan 43): mpv's
/// "Cannot seek in this stream." complaint is non-fatal for
/// live viewing (the stream is unseekable by design) and
/// keeps its previous fatal treatment for recorded playback
/// until playback has started; from then on it is non-fatal
/// for recordings too (player UI follow-up after 1.4.0).
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

    test('the seek complaint is non-fatal once recorded playback '
        'has started', () {
      expect(
        playerErrorIsFatal(seekError, live: false, alreadyPlaying: true),
        isFalse,
      );
    });

    test('the companion hint is non-fatal once recorded playback '
        'has started', () {
      expect(
        playerErrorIsFatal(
          "You can force it with '--force-seekable=yes'.",
          live: false,
          alreadyPlaying: true,
        ),
        isFalse,
      );
    });

    test('other errors stay fatal once recorded playback has started', () {
      expect(
        playerErrorIsFatal(
          'Failed to open.',
          live: false,
          alreadyPlaying: true,
        ),
        isTrue,
      );
    });
  });

  group('codec errors (measured 2026-11-23)', () {
    test('isCodecError matches the two measured messages', () {
      expect(isCodecError('Could not open codec.'), isTrue);
      expect(isCodecError('Error decoding audio.'), isTrue);
      expect(isCodecError('Failed to open.'), isFalse);
      expect(isCodecError('Cannot seek in this stream.'), isFalse);
    });

    test('codec errors stay fatal before playback starts', () {
      expect(playerErrorIsFatal('Could not open codec.', live: true), isTrue);
      expect(playerErrorIsFatal('Error decoding audio.', live: false), isTrue);
    });

    test('codec errors are non-fatal once playback has started', () {
      expect(
        playerErrorIsFatal(
          'Could not open codec.',
          live: true,
          alreadyPlaying: true,
        ),
        isFalse,
      );
      expect(
        playerErrorIsFatal(
          'Error decoding audio.',
          live: false,
          alreadyPlaying: true,
        ),
        isFalse,
      );
    });
  });

  group('playbackStoppedEarly (plan 80)', () {
    test('a stop after buffering, without completing, is an '
        'interruption', () {
      expect(
        playbackStoppedEarly(
          alreadyPlaying: true,
          completed: false,
          bufferedBeforeStop: true,
        ),
        isTrue,
      );
    });

    test('a completed playback is a normal end', () {
      expect(
        playbackStoppedEarly(
          alreadyPlaying: true,
          completed: true,
          bufferedBeforeStop: true,
        ),
        isFalse,
      );
    });

    test('a stop without fresh buffering is not flagged '
        '(a deliberate pause)', () {
      expect(
        playbackStoppedEarly(
          alreadyPlaying: true,
          completed: false,
          bufferedBeforeStop: false,
        ),
        isFalse,
      );
    });

    test('a stop before playback ever started is not an '
        'interruption (the start-failure path owns it)', () {
      expect(
        playbackStoppedEarly(
          alreadyPlaying: false,
          completed: false,
          bufferedBeforeStop: true,
        ),
        isFalse,
      );
    });
  });
}
