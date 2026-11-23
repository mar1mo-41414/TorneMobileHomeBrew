/// Playback buffer setting (plan 126): the viewer's choice of
/// how much content the playback path banks ahead of the play
/// position. The design and the seconds-to-bytes conversion
/// live in core/playback_buffer.dart; these tests pin the
/// policy math, the notifier's persistence, the player-side
/// demuxer limit that follows the choice, and the settings
/// screen wiring (including the desktop gate).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/player_cache_policy.dart';
import 'package:tmhb/ui/settings_screen.dart';

/// Lets the notifier's asynchronous restore / write-back settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('playback buffer policy', () {
    test('the choices are the standard value, then 30 / 60 / 120 s', () {
      expect(playbackBufferStandardSeconds, 0);
      expect(playbackBufferChoicesSeconds, [0, 30, 60, 120]);
    });

    test('normalize keeps choices and falls back for anything else', () {
      expect(normalizePlaybackBufferSeconds(0), 0);
      expect(normalizePlaybackBufferSeconds(30), 30);
      expect(normalizePlaybackBufferSeconds(60), 60);
      expect(normalizePlaybackBufferSeconds(120), 120);
      expect(normalizePlaybackBufferSeconds(45), 0);
      expect(normalizePlaybackBufferSeconds(-30), 0);
      expect(normalizePlaybackBufferSeconds(9999), 0);
    });

    test('parse reads the stored decimal form', () {
      expect(parsePlaybackBufferSeconds(null), 0);
      expect(parsePlaybackBufferSeconds('60'), 60);
      expect(parsePlaybackBufferSeconds(' 30 '), 30);
      // A value this build does not offer (a newer build's
      // choice, or corruption) falls back to the standard.
      expect(parsePlaybackBufferSeconds('45'), 0);
      expect(parsePlaybackBufferSeconds('abc'), 0);
      expect(parsePlaybackBufferSeconds(''), 0);
    });

    test('the standard choice has no byte cap (layer defaults apply)', () {
      expect(playbackBufferCapBytes(0), isNull);
      // An unknown value normalizes to the standard first.
      expect(playbackBufferCapBytes(45), isNull);
    });

    test('a choice converts at 3 MiB per second', () {
      expect(playbackBufferBytesPerSecond, 3 * 1024 * 1024);
      expect(playbackBufferCapBytes(30), 30 * 3 * 1024 * 1024);
      expect(playbackBufferCapBytes(60), 60 * 3 * 1024 * 1024);
      expect(playbackBufferCapBytes(120), 120 * 3 * 1024 * 1024);
    });

    test('the demuxer forward limit follows the choice', () {
      // Standard: the long-standing verified limit, untouched.
      expect(recordingDemuxerMaxBytesFor(0), recordingDemuxerMaxBytes);
      expect(recordingDemuxerMaxBytes, 32 * 1024 * 1024);
      // Otherwise the unified cap, like the proxy layers.
      expect(recordingDemuxerMaxBytesFor(60), 60 * 3 * 1024 * 1024);
      // The back limit is not the buffer setting's business.
      expect(recordingDemuxerMaxBackBytes, 16 * 1024 * 1024);
    });
  });

  group('PlaybackBufferNotifier persistence', () {
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

    test('nothing stored means the standard buffer', () async {
      final container = makeContainer();
      container.read(playbackBufferProvider);
      await flush();
      expect(container.read(playbackBufferProvider), 0);
    });

    test('a stored choice is restored', () async {
      await keyValues.write('playback_buffer_seconds', '60');
      final container = makeContainer();
      container.read(playbackBufferProvider);
      await flush();
      expect(container.read(playbackBufferProvider), 60);
    });

    test('an unknown stored value falls back to the standard', () async {
      await keyValues.write('playback_buffer_seconds', '45');
      final container = makeContainer();
      container.read(playbackBufferProvider);
      await flush();
      expect(container.read(playbackBufferProvider), 0);
    });

    test('an unparsable stored value falls back to the standard', () async {
      await keyValues.write('playback_buffer_seconds', 'lots');
      final container = makeContainer();
      container.read(playbackBufferProvider);
      await flush();
      expect(container.read(playbackBufferProvider), 0);
    });

    test('set writes the value through to the store', () async {
      final container = makeContainer();
      final notifier = container.read(playbackBufferProvider.notifier);
      await notifier.set(120);
      expect(container.read(playbackBufferProvider), 120);
      expect(await keyValues.read('playback_buffer_seconds'), '120');

      await notifier.set(0);
      expect(container.read(playbackBufferProvider), 0);
      expect(await keyValues.read('playback_buffer_seconds'), '0');
    });

    test('set normalizes a value outside the choices', () async {
      final container = makeContainer();
      final notifier = container.read(playbackBufferProvider.notifier);
      await notifier.set(45);
      expect(container.read(playbackBufferProvider), 0);
      expect(await keyValues.read('playback_buffer_seconds'), '0');
    });
  });

  group('settings screen playback buffer', () {
    Future<void> pumpBufferSetting(
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
            home: Scaffold(body: PlaybackBufferSetting()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Set<int> selectedOf(WidgetTester tester) => tester
        .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
        .selected;

    testWidgets('the standard buffer is the default shown', (tester) async {
      await pumpBufferSetting(tester, InMemoryKeyValueStore());
      expect(find.text('再生バッファ'), findsOneWidget);
      expect(find.text('標準'), findsOneWidget);
      expect(find.text('30 秒'), findsOneWidget);
      expect(find.text('60 秒'), findsOneWidget);
      expect(find.text('120 秒'), findsOneWidget);
      expect(selectedOf(tester), {0});
    });

    testWidgets('choosing 60 seconds persists the choice', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await pumpBufferSetting(tester, keyValues);
      final container = ProviderScope.containerOf(
        tester.element(find.text('再生バッファ')),
      );

      await tester.tap(find.text('60 秒'));
      await tester.pump();
      expect(selectedOf(tester), {60});
      expect(container.read(playbackBufferProvider), 60);
      expect(await keyValues.read('playback_buffer_seconds'), '60');
    });

    testWidgets('a saved choice is the one shown', (tester) async {
      final keyValues = InMemoryKeyValueStore();
      await keyValues.write('playback_buffer_seconds', '120');
      await pumpBufferSetting(tester, keyValues);
      await tester.pump();
      expect(selectedOf(tester), {120});
    });

    testWidgets('the settings screen hides the setting on desktop', (
      tester,
    ) async {
      // The widget tests run on a desktop host, where
      // isDesktopStorePlatform holds and the settings screen
      // gates the buffer section out (plan 126: the desktop
      // builds do not carry the setting this round). The
      // playback section itself must still render.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const []),
            ),
            keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('再生画質'));
      await tester.pump();
      expect(find.text('再生画質'), findsOneWidget);
      expect(find.text('再生バッファ'), findsNothing);
    });
  });
}
