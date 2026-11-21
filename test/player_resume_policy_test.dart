/// Tests for the player resume-report policy (plan 102):
/// what a finished recorded viewing reports to the unit —
/// nothing when playback never started, zero (a cleared
/// point) when it ran to the end, and the stopped-at
/// position otherwise.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_resume_policy.dart';

void main() {
  group('resumePositionToReport', () {
    test('a viewing that never started reports nothing', () {
      expect(
        resumePositionToReport(
          started: false,
          completed: false,
          position: const Duration(minutes: 12),
        ),
        isNull,
      );
      expect(
        resumePositionToReport(
          started: false,
          completed: true,
          position: Duration.zero,
        ),
        isNull,
      );
    });

    test('a completed viewing reports zero, clearing the point', () {
      expect(
        resumePositionToReport(
          started: true,
          completed: true,
          position: const Duration(minutes: 58),
        ),
        Duration.zero,
      );
    });

    test('a stopped viewing reports the stopped-at position', () {
      expect(
        resumePositionToReport(
          started: true,
          completed: false,
          position: const Duration(minutes: 12, seconds: 34),
        ),
        const Duration(minutes: 12, seconds: 34),
      );
    });

    test('a negative position is reported as zero, never negative', () {
      expect(
        resumePositionToReport(
          started: true,
          completed: false,
          position: const Duration(seconds: -5),
        ),
        Duration.zero,
      );
    });
  });
}
