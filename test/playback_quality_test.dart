/// Saved playback quality (Discord request, 2026-11-21): one
/// value in the key-value store is both the settings screen's
/// default and the starting choice of the live / title detail
/// screens, and a change on any of them writes back to it.
/// Unset means the original quality (DR).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/live_screen.dart';
import 'package:tmhb/ui/settings_screen.dart';

/// Lets the notifier's asynchronous restore / write-back settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

const _reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

void main() {
  group('PlaybackQualityNotifier persistence', () {
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

    test('nothing stored means the original quality', () async {
      final container = makeContainer();
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isFalse);
    });

    test('a stored mobile choice is restored', () async {
      await keyValues.write('playback_use_mobile', 'true');
      final container = makeContainer();
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isTrue);
    });

    test('a stored original choice is restored', () async {
      await keyValues.write('playback_use_mobile', 'false');
      final container = makeContainer();
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isFalse);
    });

    test('an unparsable stored value falls back to the original', () async {
      await keyValues.write('playback_use_mobile', 'yes');
      final container = makeContainer();
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isFalse);
    });

    test('set writes the value through to the store', () async {
      final container = makeContainer();
      final notifier = container.read(playbackQualityProvider.notifier);
      await notifier.set(true);
      expect(container.read(playbackQualityProvider), isTrue);
      expect(await keyValues.read('playback_use_mobile'), 'true');

      await notifier.set(false);
      expect(container.read(playbackQualityProvider), isFalse);
      expect(await keyValues.read('playback_use_mobile'), 'false');
    });
  });

  group('settings screen playback quality', () {
    Future<void> pumpSettings(
      WidgetTester tester,
      InMemoryKeyValueStore keyValues,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
      await tester.ensureVisible(find.text('再生画質'));
      await tester.pump();
    }

    Set<bool> selectedOf(WidgetTester tester) => tester
        .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
        .selected;

    testWidgets('DR (the original quality) is the default shown', (
      tester,
    ) async {
      final keyValues = InMemoryKeyValueStore();
      await pumpSettings(tester, keyValues);
      expect(find.text('元画質 (DR)'), findsOneWidget);
      expect(find.text('モバイル'), findsOneWidget);
      expect(selectedOf(tester), {false});
    });

    testWidgets('choosing mobile persists as the saved quality', (
      tester,
    ) async {
      final keyValues = InMemoryKeyValueStore();
      await pumpSettings(tester, keyValues);
      final container = ProviderScope.containerOf(
        tester.element(find.text('再生画質')),
      );

      await tester.tap(find.text('モバイル'));
      await tester.pump();
      expect(selectedOf(tester), {true});
      expect(container.read(playbackQualityProvider), isTrue);
      expect(await keyValues.read('playback_use_mobile'), 'true');
    });

    testWidgets('a saved mobile choice is the one shown', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('playback_use_mobile', 'true');
      await pumpSettings(tester, keyValues);
      await tester.pump();
      expect(selectedOf(tester), {true});
    });
  });

  group('live detail playback quality', () {
    const channel = LiveChannel(
      id: '0/video/LiveTuner/DTTB/ch?nid=1&tsid=1&svid=1',
      bandId: '0/video/LiveTuner/DTTB',
      channelName: 'テスト放送',
      programTitle: 'テスト番組',
      res: [
        TitleRes(
          url: 'http://192.0.2.10:58890/web/video/ch?quality=dr',
          protocolInfo: 'http-get:*:application/x-dtcp1:*',
          cleartextSize: 200000000,
          quality: 'dr',
        ),
        TitleRes(
          url: 'http://192.0.2.10:58890/web/video/ch?quality=mobile',
          protocolInfo: 'http-get:*:application/x-dtcp1:*',
          cleartextSize: 20000000,
          quality: 'mobile',
        ),
      ],
    );

    Future<void> pumpDetail(
      WidgetTester tester,
      InMemoryKeyValueStore keyValues,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(keyValues)],
          child: const MaterialApp(
            home: Scaffold(
              body: LiveChannelDetailView(reg: _reg, channel: channel),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
    }

    Set<bool> selectedOf(WidgetTester tester) => tester
        .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
        .selected;

    testWidgets('starts on the original quality when nothing is saved', (
      tester,
    ) async {
      await pumpDetail(tester, InMemoryKeyValueStore());
      expect(selectedOf(tester), {false});
    });

    testWidgets('starts from the saved quality and writes changes back', (
      tester,
    ) async {
      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('playback_use_mobile', 'true');
      await pumpDetail(tester, keyValues);
      expect(selectedOf(tester), {true});

      await tester.tap(find.text('元画質 (DR)'));
      await tester.pump();
      expect(selectedOf(tester), {false});
      expect(await keyValues.read('playback_use_mobile'), 'false');
    });
  });
}
