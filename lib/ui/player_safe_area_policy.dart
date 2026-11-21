/// Player safe-area policy (plan 105): how the player
/// screen's bottom controls — the seek bar and the
/// bottom button bar sharing its stack — clear the
/// system gesture area (the iPhone / iPad home
/// indicator, Android's gesture bar).
///
/// The player screen's body runs to the window's bottom
/// edge, and outside fullscreen media_kit's Material
/// controls take no safe-area padding of their own:
/// the theme's padding is only consulted as a fallback
/// in fullscreen, where the stock 42 px margins apply
/// on top of it. The non-fullscreen controls therefore
/// end up inside the gesture area — the seek bar's
/// touch target reaches into it and the bottom row
/// starts there — so touches near the bottom edge are
/// stolen by the system gesture and the bar cannot be
/// dragged (the owner's iPhone / iPad report: the home
/// indicator drawn over the middle of the bar).
///
/// The remedy is measured, not a fixed raise: the
/// bottom margins grow by the device's actual bottom
/// view padding, so the whole touch target and the
/// button row sit above the gesture area, while a
/// device whose system UI already stays clear of the
/// window (a zero inset — desktop, Android with button
/// navigation) keeps the layout it had.
library;

/// The bottom view padding the player screen's
/// controls must clear, sanitized: a negative or
/// non-finite value counts as no inset.
double bottomGestureInset(double viewPaddingBottom) =>
    viewPaddingBottom.isFinite && viewPaddingBottom > 0
    ? viewPaddingBottom
    : 0.0;

/// The non-fullscreen seek bar's bottom margin: the
/// standing lift off the bottom edge plus the gesture
/// inset, so the bar's whole touch target sits above
/// the gesture area.
double seekBarBottomMargin({
  required double lift,
  required double viewPaddingBottom,
}) => lift + bottomGestureInset(viewPaddingBottom);

/// The non-fullscreen bottom button bar's bottom
/// margin: exactly the gesture inset, lifting the row
/// (position indicator, fullscreen button) out of the
/// gesture area by the same amount the seek bar
/// beside it rises.
double bottomButtonBarBottomMargin(double viewPaddingBottom) =>
    bottomGestureInset(viewPaddingBottom);

/// The bottom button bar's right margin. The stock
/// theme leaves 8 px, putting the fullscreen button
/// in the bottom-right corner within the gesture
/// area's reach; 16 px — the same as the bar's left
/// margin and the seek bar's side margins — moves it
/// a step inward.
const double bottomButtonBarRightMargin = 16.0;
