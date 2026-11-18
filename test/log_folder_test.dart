/// Debug log folder opening tests (plan 71): the per-platform
/// file-manager commands, the folder being created before the
/// open, explorer.exe's meaningless exit code being ignored,
/// honest non-zero exits and start failures surfacing as
/// errors, and unsupported platforms launching nothing.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/log_folder.dart';

void main() {
  Future<Directory> tempDir(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    addTearDown(() => dir.delete(recursive: true));
    return dir;
  }

  group('fileManagerCommandFor', () {
    test('windows opens with explorer.exe and ignores its exit code', () {
      final command = fileManagerCommandFor(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        directoryPath: r'C:\store\debug_logs',
      );
      expect(command, isNotNull);
      expect(command!.executable, 'explorer.exe');
      expect(command.arguments, [r'C:\store\debug_logs']);
      expect(command.exitCodeMatters, isFalse);
    });

    test('windows normalizes forward slashes for explorer.exe', () {
      // The opener builds the path by interpolating '/' onto the
      // backslashed store path (plan 78). explorer.exe cannot
      // resolve that mixed form and opens Documents instead, so
      // the command must carry native separators throughout.
      final command = fileManagerCommandFor(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        directoryPath:
            r'C:\Users\markun\AppData\Roaming\com.markun\torne mobile HB/debug_logs',
      );
      expect(command, isNotNull);
      expect(command!.arguments, [
        r'C:\Users\markun\AppData\Roaming\com.markun\torne mobile HB\debug_logs',
      ]);
    });

    test('macos opens with open and checks its exit code', () {
      final command = fileManagerCommandFor(
        isWindows: false,
        isMacOS: true,
        isLinux: false,
        directoryPath: '/store/debug_logs',
      );
      expect(command, isNotNull);
      expect(command!.executable, 'open');
      expect(command.arguments, ['/store/debug_logs']);
      expect(command.exitCodeMatters, isTrue);
    });

    test('linux opens with xdg-open and checks its exit code', () {
      final command = fileManagerCommandFor(
        isWindows: false,
        isMacOS: false,
        isLinux: true,
        directoryPath: '/store/debug_logs',
      );
      expect(command, isNotNull);
      expect(command!.executable, 'xdg-open');
      expect(command.arguments, ['/store/debug_logs']);
      expect(command.exitCodeMatters, isTrue);
    });

    test('no desktop platform means no command', () {
      expect(
        fileManagerCommandFor(
          isWindows: false,
          isMacOS: false,
          isLinux: false,
          directoryPath: '/store/debug_logs',
        ),
        isNull,
      );
    });
  });

  group('DebugLogFolderOpener', () {
    test('creates the log folder and opens it (linux)', () async {
      final store = await tempDir('tmhb_folder_open');
      final calls = <List<String>>[];
      final opener = DebugLogFolderOpener(
        storeDirectory: store,
        isWindows: false,
        isMacOS: false,
        isLinux: true,
        runProcess: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(0, 0, '', '');
        },
      );

      final outcome = await opener.open();

      expect(outcome, DebugLogFolderOpenOutcome.opened);
      expect(calls, [
        ['xdg-open', '${store.path}/debug_logs'],
      ]);
      expect(await Directory('${store.path}/debug_logs').exists(), isTrue);
    });

    test('windows treats explorer exit code 1 as success', () async {
      final store = await tempDir('tmhb_folder_win');
      final opener = DebugLogFolderOpener(
        storeDirectory: store,
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        runProcess: (executable, arguments) async =>
            ProcessResult(0, 1, '', ''),
      );

      expect(await opener.open(), DebugLogFolderOpenOutcome.opened);
    });

    test('a non-zero exit on macos surfaces as a failure', () async {
      final store = await tempDir('tmhb_folder_mac_fail');
      final opener = DebugLogFolderOpener(
        storeDirectory: store,
        isWindows: false,
        isMacOS: true,
        isLinux: false,
        runProcess: (executable, arguments) async =>
            ProcessResult(0, 1, '', 'boom'),
      );

      await expectLater(opener.open(), throwsA(isA<ProcessException>()));
    });

    test('a process that fails to start surfaces as a failure', () async {
      final store = await tempDir('tmhb_folder_start_fail');
      final opener = DebugLogFolderOpener(
        storeDirectory: store,
        isWindows: false,
        isMacOS: false,
        isLinux: true,
        runProcess: (executable, arguments) async =>
            throw ProcessException(executable, arguments, 'not found', 2),
      );

      await expectLater(opener.open(), throwsA(isA<ProcessException>()));
    });

    test('unsupported platforms launch nothing and create nothing', () async {
      final store = await tempDir('tmhb_folder_unsupported');
      var invoked = false;
      final opener = DebugLogFolderOpener(
        storeDirectory: store,
        isWindows: false,
        isMacOS: false,
        isLinux: false,
        runProcess: (executable, arguments) async {
          invoked = true;
          return ProcessResult(0, 0, '', '');
        },
      );

      expect(await opener.open(), DebugLogFolderOpenOutcome.unsupported);
      expect(invoked, isFalse);
      expect(await Directory('${store.path}/debug_logs').exists(), isFalse);
    });
  });
}
