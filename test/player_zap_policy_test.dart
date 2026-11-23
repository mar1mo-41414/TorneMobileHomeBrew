/// Channel zapping policy tests (owner request, 2026-11-23).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_zap_policy.dart';

void main() {
  group('canZap', () {
    test('live viewing with two or more channels can zap', () {
      expect(canZap(live: true, targetCount: 2), isTrue);
      expect(canZap(live: true, targetCount: 12), isTrue);
    });

    test('a single channel has nowhere to move to', () {
      expect(canZap(live: true, targetCount: 1), isFalse);
      expect(canZap(live: true, targetCount: 0), isFalse);
    });

    test('recordings never zap, whatever the count', () {
      expect(canZap(live: false, targetCount: 5), isFalse);
      expect(canZap(live: false, targetCount: 0), isFalse);
    });
  });

  group('zapIndexAfter', () {
    test('moves one step each way inside the list', () {
      expect(zapIndexAfter(current: 1, delta: 1, count: 5), 2);
      expect(zapIndexAfter(current: 1, delta: -1, count: 5), 0);
    });

    test('wraps at both ends', () {
      expect(zapIndexAfter(current: 4, delta: 1, count: 5), 0);
      expect(zapIndexAfter(current: 0, delta: -1, count: 5), 4);
    });

    test('a two-channel band swaps either way', () {
      expect(zapIndexAfter(current: 0, delta: 1, count: 2), 1);
      expect(zapIndexAfter(current: 0, delta: -1, count: 2), 1);
      expect(zapIndexAfter(current: 1, delta: 1, count: 2), 0);
    });

    test('a degenerate count keeps the index', () {
      expect(zapIndexAfter(current: 0, delta: 1, count: 0), 0);
      expect(zapIndexAfter(current: 3, delta: -1, count: -2), 3);
    });
  });
}
