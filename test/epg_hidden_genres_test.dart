/// Hidden programme-guide genres (plan 95, Discord request
/// 2026-11-21): the notifier persists the viewer's
/// not-watched genres in the key-value store, the suppression
/// predicate drives the guide grid's blank tiles, and the
/// settings screen's 見ないジャンル page toggles them.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_genre.dart';
import 'package:tmhb/ui/settings_screen.dart';

/// Lets the notifier's asynchronous restore / write-back settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('epgGenreSuppressed', () {
    test('only listed genres with a genre are suppressed', () {
      expect(epgGenreSuppressed(3, {3, 5}), isTrue);
      expect(epgGenreSuppressed(5, {3, 5}), isTrue);
      expect(epgGenreSuppressed(0, {3, 5}), isFalse);
      expect(epgGenreSuppressed(3, const {}), isFalse);
      expect(epgGenreSuppressed(null, {3}), isFalse);
    });

    test('the pickable values are exactly the labelled genres', () {
      expect(epgGenreLevel1Values, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15]);
    });
  });

  group('HiddenEpgGenresNotifier persistence', () {
    late InMemoryKeyValueStore keyValues;

    setUp(() {
      keyValues = InMemoryKeyValueStore();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(keyValues)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('decode drops anything unparsable', () {
      expect(HiddenEpgGenresNotifier.decode(null), isEmpty);
      expect(HiddenEpgGenresNotifier.decode(''), isEmpty);
      expect(HiddenEpgGenresNotifier.decode('3,5'), {3, 5});
      expect(HiddenEpgGenresNotifier.decode('x, 7 ,,'), {7});
    });

    test('setHidden writes the sorted comma-separated form', () async {
      final container = makeContainer();
      final notifier = container.read(hiddenEpgGenresProvider.notifier);
      await notifier.setHidden(5, true);
      await notifier.setHidden(3, true);
      expect(container.read(hiddenEpgGenresProvider), {3, 5});
      expect(await keyValues.read('epg_hidden_genres'), '3,5');

      await notifier.setHidden(3, false);
      expect(container.read(hiddenEpgGenresProvider), {5});
      expect(await keyValues.read('epg_hidden_genres'), '5');
    });

    test('a fresh container restores the stored set', () async {
      await keyValues.write('epg_hidden_genres', '3,11');
      final container = makeContainer();
      container.read(hiddenEpgGenresProvider);
      await flush();
      expect(container.read(hiddenEpgGenresProvider), {3, 11});
    });
  });

  group('settings screen hidden genres', () {
    testWidgets('the genre page toggles persist through the notifier', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final keyValues = InMemoryKeyValueStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const []),
            ),
            keyValueStoreProvider.overrideWithValue(keyValues),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final tile = find.widgetWithText(ListTile, '見ないジャンル');
      await tester.ensureVisible(tile);
      await tester.pump();
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('ドラマ'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.text('ドラマ')),
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'ドラマ'));
      await tester.pump();
      expect(container.read(hiddenEpgGenresProvider), {3});
      expect(await keyValues.read('epg_hidden_genres'), '3');
    });
  });
}
