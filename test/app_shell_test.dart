/// App shell layout tests (plan 31): the rail (wide) layout must keep
/// a minimum top clearance even when the environment reports a top
/// safe-area inset smaller than the status bar drawn over the app
/// (LiveContainer on iPad, observed 2026-11-17), must not double-pad
/// when the inset is reported correctly, and the phone layout must be
/// exactly as before.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/ui/app_shell.dart';

Future<void> pumpShell(
  WidgetTester tester, {
  required Size physical,
  required double dpr,
  required double topInset,
}) async {
  tester.view.physicalSize = physical;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final logical = Size(physical.width / dpr, physical.height / dpr);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: logical,
            devicePixelRatio: dpr,
            padding: EdgeInsets.only(top: topInset),
            viewPadding: EdgeInsets.only(top: topInset),
          ),
          child: const AppShell(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('wide layout tops up a missing top inset to the floor', (
    tester,
  ) async {
    await pumpShell(
      tester,
      physical: const Size(2732, 2048),
      dpr: 2.0,
      topInset: 0,
    );
    // The rail and the first screen's app bar start at the guaranteed
    // clearance, not at the top edge of the screen.
    expect(
      tester.getTopLeft(find.byType(NavigationRail)).dy,
      wideLayoutMinTopInset,
    );
    expect(
      tester.getTopLeft(find.byType(AppBar).first).dy,
      wideLayoutMinTopInset,
    );
  });

  testWidgets('wide layout adds nothing when the inset is reported', (
    tester,
  ) async {
    await pumpShell(
      tester,
      physical: const Size(2732, 2048),
      dpr: 2.0,
      topInset: 24,
    );
    expect(tester.getTopLeft(find.byType(NavigationRail)).dy, 0);
    // The app bar itself consumes the reported inset (24 + 56 tool bar).
    expect(tester.getSize(find.byType(AppBar).first).height, 80);
  });

  testWidgets('phone layout is unchanged (bottom bar, inset in app bar)', (
    tester,
  ) async {
    await pumpShell(
      tester,
      physical: const Size(1170, 2532),
      dpr: 3.0,
      topInset: 47,
    );
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.getTopLeft(find.byType(AppBar).first).dy, 0);
    expect(tester.getSize(find.byType(AppBar).first).height, 103);
  });
}
