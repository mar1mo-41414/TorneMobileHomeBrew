/// Resume playback (plan 86, plan 85 item 1): the position the
/// nasne holds for a title becomes the player's open start, and
/// the viewer chooses between continuing and starting over.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/titles_screen.dart';

RecordedTitle _title({int? resumePointSeconds}) => RecordedTitle(
      id: '1',
      title: 'テスト番組',
      resumePointSeconds: resumePointSeconds,
    );

void main() {
  group('resumeStartOf', () {
    test('no recorded position offers nothing', () {
      expect(resumeStartOf(_title()), isNull);
    });

    test('a zero position offers nothing', () {
      expect(resumeStartOf(_title(resumePointSeconds: 0)), isNull);
    });

    test('a recorded position becomes the start duration', () {
      expect(
        resumeStartOf(_title(resumePointSeconds: 754)),
        const Duration(seconds: 754),
      );
    });
  });

  group('showResumeChoiceDialog', () {
    Future<bool?> pumpAndChoose(WidgetTester tester, String label) async {
      bool? result;
      var shown = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                shown = true;
                result = await showResumeChoiceDialog(
                  context,
                  const Duration(seconds: 754),
                );
              },
              child: const Text('開く'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(shown, isTrue);
      // The recorded position is named in the question
      // (754 seconds formats as 12分).
      expect(find.textContaining('12分'), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('continuing returns true', (tester) async {
      expect(await pumpAndChoose(tester, '続きから再生'), isTrue);
    });

    testWidgets('starting over returns false', (tester) async {
      expect(await pumpAndChoose(tester, '最初から再生'), isFalse);
    });
  });
}
