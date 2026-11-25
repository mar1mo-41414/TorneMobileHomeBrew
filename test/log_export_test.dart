/// Debug log Downloads export tests (plan 142): the export
/// names carry the export time (a re-export never overwrites
/// an earlier export's files), the exporter hands exactly the
/// recorded `debug_logs/*.log` files — byte for byte, under
/// stamped names — to the platform side, and it stays off the
/// channel when there is nothing to export or the platform
/// has no Downloads export.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/log_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.markun.tmhb/credential_downloads');
  final channelCalls = <MethodCall>[];

  setUp(() {
    channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalls.add(call);
          return '/storage/emulated/0/Download/tmhb-log';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<Directory> tempDir(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  Future<File> writeFile(Directory dir, String name, String content) async {
    final file = File('${dir.path}/$name');
    await file.create(recursive: true);
    await file.writeAsString(content);
    return file;
  }

  group('exportedLogFileName', () {
    final at = DateTime(2026, 11, 25, 9, 15, 3, 412);

    test('stamps the export time ahead of the source name', () {
      expect(
        exportedLogFileName(at, 'tmhb-debug-20261125-090000-000.log'),
        '20261125-091503-412_tmhb-debug-20261125-090000-000.log',
      );
    });

    test('two exports of the same file at different times differ', () {
      const source = 'tmhb-debug-20261125-090000-000.log';
      final earlier = exportedLogFileName(
        DateTime(2026, 11, 25, 9, 15, 3, 412),
        source,
      );
      final later = exportedLogFileName(
        DateTime(2026, 11, 25, 10, 15, 3, 412),
        source,
      );
      expect(earlier, isNot(later));
    });

    test('one export keeps the sources distinct from each other', () {
      final a = exportedLogFileName(at, 'tmhb-debug-20261125-090000-000.log');
      final b = exportedLogFileName(at, 'tmhb-debug-20261125-093000-000.log');
      expect(a, isNot(b));
    });
  });

  group('DebugLogDownloadsExporter', () {
    final fixedNow = DateTime(2026, 11, 25, 9, 15, 3, 412);

    test('no log files: noLogs, platform never called', () async {
      final store = await tempDir('tmhb_export_empty');
      var platformCalls = 0;
      final exporter = DebugLogDownloadsExporter(
        storeDirectory: store,
        platformExport: (_) async {
          platformCalls++;
          return null;
        },
        now: () => fixedNow,
      );

      final result = await exporter.export();
      expect(result.outcome, DebugLogExportOutcome.noLogs);
      expect(result.fileCount, 0);
      expect(platformCalls, 0);
    });

    test('unsupported platform: unsupported, platform never called', () async {
      final store = await tempDir('tmhb_export_unsupported');
      await writeFile(
        Directory('${store.path}/debug_logs'),
        'tmhb-debug-20261125-090000-000.log',
        'a\n',
      );
      var platformCalls = 0;
      final exporter = DebugLogDownloadsExporter(
        storeDirectory: store,
        supported: false,
        platformExport: (_) async {
          platformCalls++;
          return null;
        },
        now: () => fixedNow,
      );

      final result = await exporter.export();
      expect(result.outcome, DebugLogExportOutcome.unsupported);
      expect(platformCalls, 0);
    });

    test('exports only the log files, stamped, byte for byte', () async {
      final store = await tempDir('tmhb_export_files');
      final logDir = Directory('${store.path}/debug_logs');
      await writeFile(logDir, 'tmhb-debug-20261125-093000-000.log', 'b\n');
      await writeFile(logDir, 'tmhb-debug-20261125-090000-000.log', 'a\n');
      await writeFile(logDir, 'notes.txt', 'not a log\n');
      // Files outside debug_logs are never exported.
      await writeFile(store, 'registrations.json', '{}\n');

      List<LogExportFile>? handed;
      final exporter = DebugLogDownloadsExporter(
        storeDirectory: store,
        supported: true,
        platformExport: (files) async {
          handed = files;
          return '/storage/emulated/0/Download/tmhb-log';
        },
        now: () => fixedNow,
      );

      final result = await exporter.export();
      expect(result.outcome, DebugLogExportOutcome.exported);
      expect(result.fileCount, 2);
      expect(result.directoryPath, '/storage/emulated/0/Download/tmhb-log');
      expect(handed, isNotNull);
      // Oldest first (the collection order), stamped names,
      // exact bytes.
      expect(handed!.map((f) => f.name), [
        '20261125-091503-412_tmhb-debug-20261125-090000-000.log',
        '20261125-091503-412_tmhb-debug-20261125-093000-000.log',
      ]);
      expect(handed!.map((f) => String.fromCharCodes(f.bytes)), ['a\n', 'b\n']);
    });

    test(
      'default platform call rides the credential_downloads channel',
      () async {
        final store = await tempDir('tmhb_export_channel');
        await writeFile(
          Directory('${store.path}/debug_logs'),
          'tmhb-debug-20261125-090000-000.log',
          'a\n',
        );
        final exporter = DebugLogDownloadsExporter(
          storeDirectory: store,
          supported: true,
          now: () => fixedNow,
        );

        final result = await exporter.export();
        expect(result.outcome, DebugLogExportOutcome.exported);
        expect(result.directoryPath, '/storage/emulated/0/Download/tmhb-log');
        expect(channelCalls, hasLength(1));
        final call = channelCalls.single;
        expect(call.method, 'exportLogsToDownloads');
        final files = (call.arguments as Map)['files'] as List<dynamic>;
        expect(files, hasLength(1));
        final entry = files.single as Map;
        expect(
          entry['name'],
          '20261125-091503-412_tmhb-debug-20261125-090000-000.log',
        );
        expect(entry['bytes'], Uint8List.fromList('a\n'.codeUnits));
      },
    );
  });
}
