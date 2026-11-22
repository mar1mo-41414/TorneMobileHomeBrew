/// Player chapter policy (plan 112): how the recorded
/// playback screen moves between a title's chapter
/// points, and where the seek bar's chapter ticks sit.
///
/// The points are the unit's own silence-cut chapters
/// (see the core chapter parsing; plan 110 measured
/// them against the unit's chapter file to the
/// millisecond), so navigation is between real cuts,
/// never an even interval grid: a title without
/// validated points gets no chapter controls at all,
/// and the ±10 s skips (player_seek_policy) stay the
/// only interval movement, unchanged.
///
/// The seek bar is media_kit's, built inside its
/// controls with no slot for markers, so the ticks are
/// an overlay aligned to the bar from the same theme
/// values the controls themselves lay the bar out
/// with. The geometry functions below take those
/// values as inputs, so the alignment follows the
/// app's theming instead of duplicating constants —
/// the only media_kit-internal number they encode is
/// the desktop seek bar's downward translation over
/// its bottom button bar, which the theme does not
/// carry.
library;

import 'package:flutter/widgets.dart';

/// How far past a chapter point the previous-chapter
/// button still counts as "at" that point: within
/// this window it goes to the point before, past it
/// it returns to the point itself — the behaviour
/// viewers know from chaptered players, so a mistimed
/// press just after a cut does not need a second one
/// to undo.
const Duration chapterPreviousWindow = Duration(seconds: 2);

/// The chapter point the next-chapter button seeks
/// to: the first point strictly after [position], or
/// null when the position is at or past the last
/// point (or there are no points).
Duration? nextChapterTarget({
  required List<Duration> chapters,
  required Duration position,
}) {
  for (final point in chapters) {
    if (point > position) return point;
  }
  return null;
}

/// The chapter point the previous-chapter button
/// seeks to: the last point before [position] minus
/// [chapterPreviousWindow], or null when no point is
/// that far back. Standing exactly on a point, or
/// within the window after it, therefore lands on
/// the point before it; standing further into a
/// chapter lands on its own start.
Duration? previousChapterTarget({
  required List<Duration> chapters,
  required Duration position,
}) {
  final threshold = position - chapterPreviousWindow;
  Duration? target;
  for (final point in chapters) {
    if (point >= threshold) break;
    target = point;
  }
  return target;
}

/// The position of each chapter point as a fraction
/// of [duration] (0..1), for the seek bar ticks.
/// Empty when the duration is not (yet) known or
/// there are no chapters; a point past the duration
/// clamps to the bar's end.
List<double> chapterTickFractions({
  required List<Duration> chapters,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return const [];
  return [
    for (final point in chapters)
      (point.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0),
  ];
}

/// Where the Material controls' seek bar line sits
/// inside the video area, as the chapter ticks need
/// it: the bar's horizontal extent and the line's
/// vertical centre.
///
/// media_kit's Material seek bar is a container
/// carrying [seekBarMargin] whose line ([seekBarHeight]
/// tall) is aligned to the container's bottom, and
/// the container sits at the bottom of the controls
/// column, which is padded by [columnPadding] (the
/// theme padding, or the fullscreen safe-area padding
/// media_kit substitutes for it). The line's bottom
/// edge is therefore [columnPadding.bottom] +
/// [seekBarMargin.bottom] above the area's bottom
/// edge, and its span runs between the side margins.
({double left, double right, double centerY}) materialChapterSeekBarLine({
  required double areaWidth,
  required double areaHeight,
  required EdgeInsets columnPadding,
  required EdgeInsets seekBarMargin,
  required double seekBarHeight,
}) {
  return (
    left: columnPadding.left + seekBarMargin.left,
    right: areaWidth - columnPadding.right - seekBarMargin.right,
    centerY:
        areaHeight -
        columnPadding.bottom -
        seekBarMargin.bottom -
        seekBarHeight / 2,
  );
}

/// How far media_kit's desktop controls translate
/// their seek bar down over the bottom button bar
/// when the bar is present (media_kit_video 2.0.1's
/// layout; the theme carries no value for it).
const double desktopSeekBarTranslateWithButtonBar = 16.0;

/// Where the desktop controls' seek bar line sits
/// inside the video area, as the chapter ticks need
/// it.
///
/// The desktop bar centres its line inside the seek
/// bar container ([seekBarContainerHeight] tall,
/// carrying [seekBarMargin]), and the container sits
/// in the controls column directly above the bottom
/// button bar — whose total extent in the column is
/// [buttonBarExtent] (its height plus its vertical
/// margins) — translated down by [seekBarTranslate]
/// over that bar. The column is padded by
/// [columnPadding], as in the Material case.
({double left, double right, double centerY}) desktopChapterSeekBarLine({
  required double areaWidth,
  required double areaHeight,
  required EdgeInsets columnPadding,
  required EdgeInsets seekBarMargin,
  required double seekBarContainerHeight,
  required double buttonBarExtent,
  required double seekBarTranslate,
}) {
  final containerBottom =
      columnPadding.bottom +
      buttonBarExtent -
      seekBarTranslate +
      seekBarMargin.bottom;
  return (
    left: columnPadding.left + seekBarMargin.left,
    right: areaWidth - columnPadding.right - seekBarMargin.right,
    centerY: areaHeight - containerBottom - seekBarContainerHeight / 2,
  );
}
