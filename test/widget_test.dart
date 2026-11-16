/// App shell smoke test (replaces the scaffold counter test).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/main.dart';

void main() {
  testWidgets('shell shows the app title and the playback notice',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TmhbApp()));
    await tester.pump();
    expect(find.text('torne mobile HomeBrew エディション'), findsOneWidget);
    expect(find.textContaining('再生: 未実装'), findsOneWidget);
  });
}
