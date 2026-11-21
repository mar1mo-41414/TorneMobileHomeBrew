/// Player chapter policy tests (plan 112): the
/// previous / next navigation boundaries and the seek
/// bar tick geometry.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_chapter_policy.dart';

void main() {
  const chapters = [
    Duration.zero,
    Duration(seconds: 100),
    Duration(seconds: 250),
    Duration(seconds: 400),
  ];

  group('nextChapterTarget', () {
    Duration? next(Duration position) =>
        nextChapterTarget(chapters: chapters, position: position);

    test('from the start, the first cut after it', () {
      expect(next(Duration.zero), const Duration(seconds: 100));
    });

    test('between cuts, the upcoming cut', () {
      expect(next(const Duration(seconds: 99)), const Duration(seconds: 100));
      expect(next(const Duration(seconds: 101)), const Duration(seconds: 250));
    });

    test('standing exactly on a cut goes to the following one', () {
      expect(next(const Duration(seconds: 100)), const Duration(seconds: 250));
      expect(next(const Duration(seconds: 250)), const Duration(seconds: 400));
    });

    test('at and past the last cut there is no next', () {
      expect(next(const Duration(seconds: 400)), isNull);
      expect(next(const Duration(seconds: 999)), isNull);
    });

    test('no chapters, no target', () {
      expect(
        nextChapterTarget(chapters: const [], position: Duration.zero),
        isNull,
      );
    });
  });

  group('previousChapterTarget', () {
    Duration? prev(Duration position) =>
        previousChapterTarget(chapters: chapters, position: position);

    test('at the start there is no previous', () {
      expect(prev(Duration.zero), isNull);
      expect(prev(const Duration(seconds: 1)), isNull);
      // Exactly the window past the start point: the
      // start point is not before position - window.
      expect(prev(const Duration(seconds: 2)), isNull);
    });

    test('well into the first chapter, back to its start', () {
      expect(prev(const Duration(seconds: 50)), Duration.zero);
      expect(prev(const Duration(seconds: 99)), Duration.zero);
    });

    test('within the window after a cut, the cut before it', () {
      // 1 s into the chapter at 100 s: previous means
      // the chapter before, not this one's start.
      expect(prev(const Duration(seconds: 101)), Duration.zero);
      // Exactly at cut + window the cut is not yet
      // "before" the threshold either.
      expect(prev(const Duration(seconds: 102)), Duration.zero);
    });

    test('past the window, the current chapter start', () {
      expect(prev(const Duration(seconds: 103)), const Duration(seconds: 100));
      expect(prev(const Duration(seconds: 249)), const Duration(seconds: 100));
    });

    test('standing on a later cut goes to the one before', () {
      expect(prev(const Duration(seconds: 250)), const Duration(seconds: 100));
    });

    test('past the last cut, the last cut', () {
      expect(prev(const Duration(seconds: 999)), const Duration(seconds: 400));
    });

    test('no chapters, no target', () {
      expect(
        previousChapterTarget(
          chapters: const [],
          position: const Duration(seconds: 10),
        ),
        isNull,
      );
    });
  });

  group('chapterTickFractions', () {
    test('points map onto the duration', () {
      expect(
        chapterTickFractions(
          chapters: chapters,
          duration: const Duration(seconds: 500),
        ),
        [0.0, 0.2, 0.5, 0.8],
      );
    });

    test('an unknown duration has no fractions', () {
      expect(
        chapterTickFractions(chapters: chapters, duration: Duration.zero),
        isEmpty,
      );
    });

    test('a point past the duration clamps to the end', () {
      expect(
        chapterTickFractions(
          chapters: const [Duration(seconds: 600)],
          duration: const Duration(seconds: 500),
        ),
        [1.0],
      );
    });
  });

  group('materialChapterSeekBarLine', () {
    test('the app non-fullscreen theme values', () {
      // seekBarMargin 16 / 16 / bottom 12 (the lift),
      // line 4 tall, no column padding.
      final line = materialChapterSeekBarLine(
        areaWidth: 800,
        areaHeight: 450,
        columnPadding: EdgeInsets.zero,
        seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
        seekBarHeight: 4,
      );
      expect(line.left, 16);
      expect(line.right, 784);
      expect(line.centerY, 450 - 12 - 2);
    });

    test('the gesture inset raises the line with the bar', () {
      // Bottom margin 12 + 34 of view padding, as the
      // safe-area policy computes it on an iPhone.
      final line = materialChapterSeekBarLine(
        areaWidth: 800,
        areaHeight: 450,
        columnPadding: EdgeInsets.zero,
        seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: 46),
        seekBarHeight: 4,
      );
      expect(line.centerY, 450 - 46 - 2);
    });

    test('fullscreen: safe-area column padding plus the stock margin', () {
      final line = materialChapterSeekBarLine(
        areaWidth: 800,
        areaHeight: 450,
        columnPadding: const EdgeInsets.only(bottom: 20),
        seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: 42),
        seekBarHeight: 4,
      );
      expect(line.centerY, 450 - 20 - 42 - 2);
    });
  });

  group('desktopChapterSeekBarLine', () {
    test('the app desktop theme values', () {
      // Container 48 tall centred line, button bar
      // extent 56, translated 16 down over it, seek
      // bar margins horizontal-only.
      final line = desktopChapterSeekBarLine(
        areaWidth: 800,
        areaHeight: 450,
        columnPadding: EdgeInsets.zero,
        seekBarMargin: const EdgeInsets.symmetric(horizontal: 16),
        seekBarContainerHeight: 48,
        buttonBarExtent: 56,
        seekBarTranslate: desktopSeekBarTranslateWithButtonBar,
      );
      expect(line.left, 16);
      expect(line.right, 784);
      // Container bottom at 56 - 16 = 40 above the
      // area bottom; the line centres 24 above that.
      expect(line.centerY, 450 - 40 - 24);
    });

    test('without a bottom button bar there is no translation', () {
      final line = desktopChapterSeekBarLine(
        areaWidth: 800,
        areaHeight: 450,
        columnPadding: EdgeInsets.zero,
        seekBarMargin: const EdgeInsets.symmetric(horizontal: 16),
        seekBarContainerHeight: 48,
        buttonBarExtent: 0,
        seekBarTranslate: 0,
      );
      expect(line.centerY, 450 - 24);
    });
  });
}
