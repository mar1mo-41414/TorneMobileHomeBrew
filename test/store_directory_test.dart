/// Plan 39: the one-time desktop migration of the store files
/// from the legacy documents directory to the application
/// support directory.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/bootstrap.dart';
import 'package:tmhb/app/store_directory.dart';

void main() {
  group('migrateLegacyStoreFiles', () {
    late Directory root;
    late Directory from;
    late Directory to;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('tmhb_migrate_');
      from = Directory('${root.path}/documents')..createSync();
      to = Directory('${root.path}/support');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> write(File file, String contents) async {
      await file.parent.create(recursive: true);
      await file.writeAsString(contents);
    }

    test('moves both store files and the debug logs', () async {
      await write(File('${from.path}/$registrationFileName'), 'regs');
      await write(File('${from.path}/$keyValueFileName'), 'kv');
      await write(
        File('${from.path}/$debugLogsDirectoryName/a.log'),
        'log-a',
      );

      await migrateLegacyStoreFiles(from: from, to: to);

      expect(await File('${to.path}/$registrationFileName').readAsString(),
          'regs');
      expect(
          await File('${to.path}/$keyValueFileName').readAsString(), 'kv');
      expect(
        await File('${to.path}/$debugLogsDirectoryName/a.log')
            .readAsString(),
        'log-a',
      );
      // The legacy location is left clean.
      expect(await File('${from.path}/$registrationFileName').exists(),
          isFalse);
      expect(await File('${from.path}/$keyValueFileName').exists(), isFalse);
      expect(
          await Directory('${from.path}/$debugLogsDirectoryName').exists(),
          isFalse);
    });

    test('never overwrites a file already at the destination', () async {
      await write(File('${from.path}/$registrationFileName'), 'legacy');
      await write(File('${to.path}/$registrationFileName'), 'current');

      await migrateLegacyStoreFiles(from: from, to: to);

      expect(await File('${to.path}/$registrationFileName').readAsString(),
          'current');
      // The unmigrated legacy file is left in place, not deleted:
      // the migration must never destroy data.
      expect(await File('${from.path}/$registrationFileName').exists(),
          isTrue);
    });

    test('merges debug logs file by file', () async {
      await write(File('${from.path}/$debugLogsDirectoryName/a.log'), 'a');
      await write(File('${from.path}/$debugLogsDirectoryName/b.log'), 'b');
      await write(File('${to.path}/$debugLogsDirectoryName/b.log'), 'kept');

      await migrateLegacyStoreFiles(from: from, to: to);

      expect(
        await File('${to.path}/$debugLogsDirectoryName/a.log')
            .readAsString(),
        'a',
      );
      expect(
        await File('${to.path}/$debugLogsDirectoryName/b.log')
            .readAsString(),
        'kept',
      );
      // b.log could not move, so the legacy directory stays.
      expect(
          await Directory('${from.path}/$debugLogsDirectoryName').exists(),
          isTrue);
      expect(
          await File('${from.path}/$debugLogsDirectoryName/a.log').exists(),
          isFalse);
    });

    test('is a no-op when there is nothing to migrate', () async {
      await migrateLegacyStoreFiles(from: from, to: to);
      expect(await to.list().isEmpty, isTrue);
    });

    test('running it twice changes nothing the second time', () async {
      await write(File('${from.path}/$registrationFileName'), 'regs');
      await migrateLegacyStoreFiles(from: from, to: to);
      await migrateLegacyStoreFiles(from: from, to: to);
      expect(await File('${to.path}/$registrationFileName').readAsString(),
          'regs');
    });
  });
}
