/// Tests for the player safe-area policy (plan 105):
/// the bottom margins of the player screen's
/// non-fullscreen controls grow by the device's actual
/// bottom view padding, so the seek bar's touch target
/// and the bottom button row clear the home indicator,
/// and a device with no inset keeps the layout it had.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_safe_area_policy.dart';

void main() {
  group('bottomGestureInset', () {
    test('passes a real inset through', () {
      expect(bottomGestureInset(34), 34); // iPhone, portrait.
      expect(bottomGestureInset(21), 21); // iPhone, landscape.
      expect(bottomGestureInset(20), 20); // iPad.
    });

    test('no inset stays no inset', () {
      expect(bottomGestureInset(0), 0);
    });

    test('nonsense values count as no inset', () {
      expect(bottomGestureInset(-4), 0);
      expect(bottomGestureInset(double.nan), 0);
      expect(bottomGestureInset(double.infinity), 0);
    });
  });

  group('seekBarBottomMargin', () {
    test('the lift alone applies without an inset', () {
      expect(seekBarBottomMargin(lift: 12, viewPaddingBottom: 0), 12);
    });

    test('the inset adds to the lift', () {
      expect(seekBarBottomMargin(lift: 12, viewPaddingBottom: 34), 46);
      expect(seekBarBottomMargin(lift: 12, viewPaddingBottom: 20), 32);
    });
  });

  group('bottomButtonBarBottomMargin', () {
    test('matches the inset exactly', () {
      expect(bottomButtonBarBottomMargin(34), 34);
      expect(bottomButtonBarBottomMargin(20), 20);
      expect(bottomButtonBarBottomMargin(0), 0);
    });
  });

  test('the fullscreen button margin moves in from the stock 8 px', () {
    expect(bottomButtonBarRightMargin, greaterThan(8.0));
  });
}
