/// Plan 86.4 (#4): the no-device guidance is shared across tabs,
/// and a failed discovery in settings shows the cause-based
/// checklist with a retry instead of ending at "enter an address".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/settings_screen.dart';
import 'package:tmhb/ui/titles_screen.dart';
import 'package:tmhb/ui/widgets.dart';

class _EmptyDiscovery implements DiscoveryService {
  int calls = 0;

  @override
  Future<List<NasneDevice>> discover({Duration? timeout}) async {
    calls++;
    return const [];
  }

  @override
  Future<NasneDevice> describe(Uri location) async =>
      NasneDevice.direct(location.host);
}

void main() {
  testWidgets('NoDeviceView shows the prompt and fires onRegister', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(home: NoDeviceView(onRegister: () => tapped = true)),
    );
    expect(find.text('nasne が登録されていません'), findsOneWidget);
    expect(find.text('設定で登録する'), findsOneWidget);
    await tester.tap(find.text('設定で登録する'));
    expect(tapped, isTrue);
  });

  testWidgets('DiscoveryChecklist renders every checklist item', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DiscoveryChecklist())),
    );
    expect(find.text('見つからないときは、次の点を確認してください。'), findsOneWidget);
    for (final item in discoveryChecklistItems) {
      expect(find.text(item), findsOneWidget);
    }
  });

  testWidgets('titles tab without a device jumps to the settings tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TitlesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nasne が登録されていません'), findsOneWidget);
    await tester.tap(find.text('設定で登録する'));
    await tester.pump();
    expect(container.read(tabIndexProvider), AppTabs.settings);
  });

  testWidgets('settings discovery finding nothing shows checklist + retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final discovery = _EmptyDiscovery();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [discoveryServiceProvider.overrideWithValue(discovery)],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAN 内の nasne を探す'));
    await tester.pumpAndSettle();
    expect(find.text('見つかりませんでした。'), findsOneWidget);
    expect(find.text('もう一度探す'), findsOneWidget);
    for (final item in discoveryChecklistItems) {
      expect(find.text(item), findsOneWidget);
    }
    // The retry runs discovery again.
    await tester.tap(find.text('もう一度探す'));
    await tester.pumpAndSettle();
    expect(discovery.calls, 2);
  });
}
