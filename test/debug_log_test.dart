/// Debug mode tests (plan 28): the file sink (naming, rotation,
/// caps), the settings persistence, the native-transport fallback,
/// and the source audit that keeps key material out of log lines.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/ake_socket.dart';
import 'package:tmhb/app/debug_log.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('FileDebugLogSink', () {
    test('writes timestamped, category-tagged lines under debug_logs',
        () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_debug_test');
      addTearDown(() => dir.delete(recursive: true));
      final sink = FileDebugLogSink(dir);
      sink.write(DiagCategory.ake, 'stage: test line');
      sink.write(DiagCategory.ui, 'playback start failed: sample');
      await sink.flush();
      final logDir = Directory('${dir.path}/debug_logs');
      final files = await logDir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      expect(
        files.single.uri.pathSegments.last,
        matches(RegExp(r'^tmhb-debug-\d{8}-\d{6}-\d{3}\.log$')),
      );
      final content = await files.single.readAsString();
      expect(content, contains('[ake] stage: test line'));
      expect(content, contains('[ui] playback start failed: sample'));
    });

    test('rotation keeps the file count within the cap', () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_debug_test');
      addTearDown(() => dir.delete(recursive: true));
      final sink = FileDebugLogSink(
        dir,
        maxFiles: 2,
        maxFileBytes: 200,
        maxTotalBytes: 1 << 20,
      );
      for (var i = 0; i < 60; i++) {
        sink.write(DiagCategory.ake, 'line $i ${'x' * 40}');
      }
      await sink.flush();
      final logDir = Directory('${dir.path}/debug_logs');
      final files = await logDir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      expect(files.length, lessThanOrEqualTo(2));
      var total = 0;
      for (final f in files) {
        total += await f.length();
      }
      // Bounded: at most maxFiles files of roughly maxFileBytes
      // plus one in-flight line each.
      expect(total, lessThan(200 * 2 + 200));
    });
  });

  group('DebugSettings', () {
    test('category set round-trips through its encoding', () {
      const settings = DebugSettings(
        master: true,
        categories: {DiagCategory.ake, DiagCategory.ui},
      );
      final decoded = DebugSettings.decodeCategories(
        settings.encodeCategories(),
      );
      expect(decoded, {DiagCategory.ake, DiagCategory.ui});
      // Null means the default: all categories.
      expect(
        DebugSettings.decodeCategories(null),
        DiagCategory.values.toSet(),
      );
    });

    test('the notifier persists master and categories', () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container.read(debugSettingsProvider);
      await Future<void>.delayed(Duration.zero);
      await container.read(debugSettingsProvider.notifier).setMaster(true);
      await container
          .read(debugSettingsProvider.notifier)
          .setCategory(DiagCategory.epg, false);
      expect(await store.read('debug_mode_enabled'), 'true');
      final stored = await store.read('debug_categories');
      expect(stored, isNotNull);
      expect(stored!.split(','), isNot(contains('epg')));
      expect(stored.split(','), contains('ake'));

      // A fresh container loads the persisted settings.
      final container2 = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container2.dispose);
      container2.read(debugSettingsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final loaded = container2.read(debugSettingsProvider);
      expect(loaded.master, isTrue);
      expect(loaded.categories, isNot(contains(DiagCategory.epg)));
      expect(loaded.categories, contains(DiagCategory.ake));
    });

    test('diagLogProvider records only when master and category are on',
        () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_debug_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          storeDirectoryProvider.overrideWithValue(dir),
        ],
      );
      addTearDown(container.dispose);
      final log = container.read(diagLogProvider);
      // Master off by default: nothing is enabled.
      expect(log.enabledFor(DiagCategory.ake), isFalse);
      log(DiagCategory.ake, 'must not be written');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await Directory('${dir.path}/debug_logs').exists(), isFalse);

      await container.read(debugSettingsProvider.notifier).setMaster(true);
      expect(log.enabledFor(DiagCategory.ake), isTrue);
      log(DiagCategory.ake, 'must be written');
      // The sink chain is fire-and-forget; poll briefly for the file.
      final logDir = Directory('${dir.path}/debug_logs');
      var found = false;
      for (var i = 0; i < 50 && !found; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (await logDir.exists()) {
          await for (final e in logDir.list()) {
            if (e is File &&
                (await e.readAsString()).contains('must be written')) {
              found = true;
            }
          }
        }
      }
      expect(found, isTrue);
    });
  });

  group('native AKE transport fallback', () {
    // Linux is a native-socket platform too (plan 39.6) and the
    // test host is Linux, so the factory now enters the native
    // path here. Simulate the channel being unavailable (as in a
    // test process) to exercise the documented fallback.
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.markun.tmhb/ake_socket'),
        (call) async => throw MissingPluginException(),
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.markun.tmhb/ake_socket_events'),
        (call) async => null,
      );
    });

    test('when the native channel is unavailable it falls back to a '
        'working dart socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close());
      server.listen((socket) {
        socket.listen((data) => socket.add(data)); // echo
      });
      final connection = await nativeAkeConnectionFactory(
        '127.0.0.1',
        server.port,
      );
      connection.send(Uint8List.fromList([1, 2, 3]));
      final echoed = await connection.incoming.first.timeout(
        const Duration(seconds: 5),
      );
      expect(echoed, [1, 2, 3]);
      await connection.close();
    });
  });

  group('log call-site audit', () {
    test('no diagnostics call site interpolates key material', () async {
      // Every line mentioning a DiagCategory (plus the two lines
      // after it, for wrapped calls) is scanned for interpolations
      // of secret-bearing identifiers. Stage names like "signature
      // verified" are fine; VALUES are not.
      final banned = RegExp(
        r'\$\{?[\w.()]*?(authkey|privatekey|privatescalar|sharedsecret|'
        r'contentkey|nonce|ephemeral|signature|masked|certificate|'
        r'credentials|exchange_?key(?!label))',
        caseSensitive: false,
      );
      final libDir = Directory('lib');
      final files = await libDir
          .list(recursive: true)
          .where((e) => e is File && e.path.endsWith('.dart'))
          .cast<File>()
          .toList();
      expect(files, isNotEmpty);
      final offenders = <String>[];
      for (final file in files) {
        final lines = await file.readAsLines();
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('DiagCategory.')) continue;
          final window = [
            lines[i],
            if (i + 1 < lines.length) lines[i + 1],
            if (i + 2 < lines.length) lines[i + 2],
          ].join('\n');
          if (banned.hasMatch(window)) {
            offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });
}
