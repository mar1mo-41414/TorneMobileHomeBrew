/// Tests for the player track policy (plan 53): the subtitle
/// toggle appears only when the stream carries a caption
/// track, the audio switcher only with two or more audio
/// tracks, labels follow the broadcast main/sub convention,
/// and the subtitle selection resolves to "no track" unless
/// captions are on and a track exists.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_track_policy.dart';

void main() {
  group('canToggleSubtitles', () {
    test('offered when a caption track exists', () {
      expect(canToggleSubtitles(1), isTrue);
      expect(canToggleSubtitles(2), isTrue);
    });

    test('not offered without caption tracks', () {
      expect(canToggleSubtitles(0), isFalse);
    });
  });

  group('canSwitchAudio', () {
    test('offered with two or more audio tracks', () {
      expect(canSwitchAudio(2), isTrue);
      expect(canSwitchAudio(3), isTrue);
    });

    test('not offered with a single audio track', () {
      expect(canSwitchAudio(1), isFalse);
      expect(canSwitchAudio(0), isFalse);
    });
  });

  group('audioTrackLabel', () {
    test('first track is the main audio, second is the sub audio', () {
      expect(audioTrackLabel(0), '主音声');
      expect(audioTrackLabel(1), '副音声');
    });

    test('further tracks fall back to a numbered label', () {
      expect(audioTrackLabel(2), '音声3');
    });
  });

  group('subtitleTrackIdToSelect', () {
    test('on selects the first subtitle track', () {
      expect(
        subtitleTrackIdToSelect(subtitlesOn: true, subtitleTrackIds: ['3', '4']),
        '3',
      );
    });

    test('off selects no track', () {
      expect(
        subtitleTrackIdToSelect(subtitlesOn: false, subtitleTrackIds: ['3']),
        isNull,
      );
    });

    test('on without tracks still selects no track', () {
      expect(
        subtitleTrackIdToSelect(subtitlesOn: true, subtitleTrackIds: const []),
        isNull,
      );
    });
  });

  group('selectedAudioIndex', () {
    test('finds the selected track', () {
      expect(
        selectedAudioIndex(selectedId: '2', trackIds: ['1', '2']),
        1,
      );
    });

    test('falls back to the first track for auto/unknown selections', () {
      expect(
        selectedAudioIndex(selectedId: 'auto', trackIds: ['1', '2']),
        0,
      );
      expect(
        selectedAudioIndex(selectedId: null, trackIds: ['1', '2']),
        0,
      );
    });
  });
}
