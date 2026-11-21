/// Regression tests for the recorded-titles pane decision
/// (external report, 2026-11-21): on a device whose window is at
/// least the two-pane breakpoint wide while the list itself —
/// narrowed by the app shell's navigation rail — is not (a
/// 1024-wide iPad in landscape, a Split View or Stage Manager
/// window), tapping a title did nothing at all. The tap judged
/// "wide" from the MediaQuery window width and only updated the
/// selection, while the layout judged "narrow" from its own
/// constraints and showed no detail pane; the narrow path's
/// detail page was never pushed either, so the playback screen
/// was unreachable. The layout and the tap now share one width:
/// the width the list actually gets.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/titles_screen.dart';

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

const _title = RecordedTitle(id: '1', title: 'テスト番組', channelName: 'テスト放送');

/// A titles notifier serving one fixed, complete stage — the
/// override stand-in for the device-backed load (plan 103).
class _StaticTitlesNotifier extends TitlesNotifier {
  _StaticTitlesNotifier(super.reg);

  @override
  Stream<TitleListProgress> build() =>
      Stream.value(const TitleListProgress([_title], complete: true));
}

/// Pumps the titles screen the way the wide app shell hosts it:
/// beside a navigation rail, so the screen's own width is the
/// window width minus the rail — the gap the bug lived in. With
/// [withRail] false the screen gets the full window width, as in
/// the phone (bottom bar) layout.
Future<void> _pumpTitles(
  WidgetTester tester, {
  required Size size,
  bool withRail = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        registrationStoreProvider.overrideWithValue(
          InMemoryRegistrationStore(const [_reg]),
        ),
        titlesProvider.overrideWith2((reg) => _StaticTitlesNotifier(reg)),
        titleCountsProvider.overrideWith(
          (ref, reg) async => const TitleCounts(1, 3000),
        ),
        channelsProvider.overrideWith((ref, reg) async => <Channel>[]),
        titleThumbnailProvider.overrideWith((ref, key) async => null),
        credentialSummaryProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        home: withRail
            ? Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: 3,
                      onDestinationSelected: (_) {},
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          label: Text('ホーム'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.live_tv_outlined),
                          label: Text('TV視聴'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.event_note_outlined),
                          label: Text('予約'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.video_library_outlined),
                          label: Text('録画済み'),
                        ),
                      ],
                    ),
                    const VerticalDivider(thickness: 1, width: 1),
                    const Expanded(child: TitlesScreen()),
                  ],
                ),
              )
            : const TitlesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('テスト番組'), findsOneWidget);
}

void main() {
  testWidgets(
    'window past the breakpoint but list narrower: tap opens the detail page',
    (tester) async {
      // A 1024-wide iPad in landscape: the window clears the
      // 1000 breakpoint, the list beside the rail does not. The
      // tap must take the narrow path and push the detail page —
      // before the fix it only set the selection and the screen
      // appeared dead.
      await _pumpTitles(tester, size: const Size(1024, 768));
      await tester.tap(find.text('テスト番組'));
      await tester.pumpAndSettle();
      expect(find.byType(TitleDetailPage), findsOneWidget);
      expect(find.text('再生'), findsOneWidget);
    },
  );

  testWidgets('genuinely wide: tap shows the detail in the second pane', (
    tester,
  ) async {
    await _pumpTitles(tester, size: const Size(1280, 800));
    expect(find.text('タイトルを選択してください'), findsOneWidget);
    await tester.tap(find.text('テスト番組'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsNothing);
    expect(find.byType(TitleDetailView), findsOneWidget);
    expect(find.text('再生'), findsOneWidget);
  });

  testWidgets('phone width: tap pushes the detail page', (tester) async {
    await _pumpTitles(tester, size: const Size(390, 844), withRail: false);
    await tester.tap(find.text('テスト番組'));
    await tester.pumpAndSettle();
    expect(find.byType(TitleDetailPage), findsOneWidget);
    expect(find.text('再生'), findsOneWidget);
  });
}
