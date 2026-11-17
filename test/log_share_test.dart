/// Debug log sharing tests (plan 46): the collection only ever
/// picks up `debug_logs/*.log`, staging produces byte-identical
/// copies under the share staging directory, and the sharer
/// invokes the platform channel only when there is something to
/// share on a supported platform.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/log_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.markun.tmhb/share_files');
  final channelCalls = <MethodCall>[];

  setUp(() {
    channelCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalls.add(call);
          return null;
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

  group('collectDebugLogFiles', () {
    test('lists only .log files under debug_logs, oldest first', () async {
      final docs = await tempDir('tmhb_share_collect');
      final logDir = Directory('${docs.path}/debug_logs');
      await writeFile(logDir, 'tmhb-debug-20261117-120000-000.log', 'b\n');
      await writeFile(logDir, 'tmhb-debug-20261117-090000-000.log', 'a\n');
      await writeFile(logDir, 'notes.txt', 'not a log\n');
      // Files outside debug_logs are never collected.
      await writeFile(docs, 'registrations.json', '{}\n');

      final files = await collectDebugLogFiles(docs);
      expect(files.map((f) => f.path.split('/').last), [
        'tmhb-debug-20261117-090000-000.log',
        'tmhb-debug-20261117-120000-000.log',
      ]);
    });

    test('returns empty when debug_logs does not exist', () async {
      final docs = await tempDir('tmhb_share_collect_missing');
      expect(await collectDebugLogFiles(docs), isEmpty);
    });
  });

  group('stageDebugLogFiles', () {
    test('copies contents and clears previously staged files', () async {
      final docs = await tempDir('tmhb_share_stage_src');
      final stagingParent = await tempDir('tmhb_share_stage_dst');
      final source = await writeFile(
        Directory('${docs.path}/debug_logs'),
        'tmhb-debug-20261117-090000-000.log',
        'log body\n',
      );
      await writeFile(
        Directory('${stagingParent.path}/$logShareStagingDirName'),
        'stale.log',
        'old share\n',
      );

      final staged = await stageDebugLogFiles([source], stagingParent);
      expect(staged, hasLength(1));
      expect(
        staged.single.path,
        '${stagingParent.path}/$logShareStagingDirName/'
        'tmhb-debug-20261117-090000-000.log',
      );
      expect(await staged.single.readAsString(), 'log body\n');
      final stagingDir = Directory(
        '${stagingParent.path}/$logShareStagingDirName',
      );
      final names = await stagingDir
          .list()
          .map((e) => e.path.split('/').last)
          .toList();
      expect(names, ['tmhb-debug-20261117-090000-000.log']);
    });
  });

  group('DebugLogSharer', () {
    Future<DebugLogSharer> sharerWithLogs(
      Directory docs,
      Directory stagingParent, {
      bool supported = true,
    }) async {
      await writeFile(
        Directory('${docs.path}/debug_logs'),
        'tmhb-debug-20261117-090000-000.log',
        'log body\n',
      );
      return DebugLogSharer(
        documentsDirectory: docs,
        stagingDirectory: () async => stagingParent,
        supported: supported,
      );
    }

    test('no logs: returns noLogs without touching the channel', () async {
      final docs = await tempDir('tmhb_share_none');
      final stagingParent = await tempDir('tmhb_share_none_stage');
      final sharer = DebugLogSharer(
        documentsDirectory: docs,
        stagingDirectory: () async => stagingParent,
        supported: true,
      );
      expect(await sharer.share(), DebugLogShareOutcome.noLogs);
      expect(channelCalls, isEmpty);
    });

    test('unsupported: returns unsupported without invoking', () async {
      final docs = await tempDir('tmhb_share_unsupported');
      final stagingParent = await tempDir('tmhb_share_unsupported_stage');
      final sharer = await sharerWithLogs(
        docs,
        stagingParent,
        supported: false,
      );
      expect(await sharer.share(), DebugLogShareOutcome.unsupported);
      expect(channelCalls, isEmpty);
    });

    test('shares staged copies with their paths and the origin', () async {
      final docs = await tempDir('tmhb_share_ok');
      final stagingParent = await tempDir('tmhb_share_ok_stage');
      final sharer = await sharerWithLogs(docs, stagingParent);
      final outcome = await sharer.share(
        origin: const Rect.fromLTWH(10, 20, 300, 48),
      );
      expect(outcome, DebugLogShareOutcome.shared);
      expect(channelCalls, hasLength(1));
      final call = channelCalls.single;
      expect(call.method, 'shareFiles');
      final args = call.arguments as Map<dynamic, dynamic>;
      expect(args['paths'], [
        '${stagingParent.path}/$logShareStagingDirName/'
            'tmhb-debug-20261117-090000-000.log',
      ]);
      expect(args['originX'], 10.0);
      expect(args['originY'], 20.0);
      expect(args['originWidth'], 300.0);
      expect(args['originHeight'], 48.0);
    });
  });
}
