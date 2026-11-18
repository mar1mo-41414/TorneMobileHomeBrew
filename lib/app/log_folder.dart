/// Opening the debug log folder on desktop (plan 71).
///
/// Log sharing (plan 46) is built on the mobile share sheet, so
/// on desktop the settings action could only answer that logs
/// cannot be shared there — yet a desktop install is exactly
/// where the user can act on a folder directly. On desktop the
/// action therefore opens `<store>/debug_logs/` in the OS file
/// manager (Explorer / Finder / xdg-open) instead.
///
/// The folder is created first when it does not exist yet (debug
/// mode may never have recorded anything), so the button never
/// lands on a missing path. Failures are reported to the caller,
/// never swallowed: the settings screen turns them into a
/// visible error — the same defensive line as plan 69.5, where a
/// picker failure presented as a button that did nothing.
library;

import 'dart:io';

import 'bootstrap.dart';

/// A command that opens a directory in a desktop file manager.
class FileManagerCommand {
  const FileManagerCommand(
    this.executable,
    this.arguments, {
    required this.exitCodeMatters,
  });

  /// The program to run (`explorer.exe`, `open`, `xdg-open`).
  final String executable;

  /// Its arguments: the directory to open.
  final List<String> arguments;

  /// Whether a non-zero exit code means the open failed.
  ///
  /// explorer.exe answers 1 even when it successfully opened the
  /// folder (its exit code has never been a success signal), so
  /// on Windows only a failure to start the process counts.
  /// `open` and `xdg-open` report honestly and are checked.
  final bool exitCodeMatters;
}

/// The file-manager command that opens [directoryPath] on the
/// platform selected by [isWindows] / [isMacOS] / [isLinux], or
/// null when none of them applies (mobile: no desktop file
/// manager to open).
FileManagerCommand? fileManagerCommandFor({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required String directoryPath,
}) {
  if (isWindows) {
    return FileManagerCommand('explorer.exe', [
      directoryPath,
    ], exitCodeMatters: false);
  }
  if (isMacOS) {
    return FileManagerCommand('open', [directoryPath], exitCodeMatters: true);
  }
  if (isLinux) {
    return FileManagerCommand('xdg-open', [
      directoryPath,
    ], exitCodeMatters: true);
  }
  return null;
}

/// Outcome of a [DebugLogFolderOpener.open] attempt.
enum DebugLogFolderOpenOutcome {
  /// The file manager was launched on the log folder.
  opened,

  /// This platform has no desktop file manager (anything other
  /// than Windows / macOS / Linux). Nothing was launched.
  unsupported,
}

/// Opens `<store>/debug_logs/` in the OS file manager.
class DebugLogFolderOpener {
  DebugLogFolderOpener({
    required this._storeDirectory,
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
    bool? isWindows,
    bool? isMacOS,
    bool? isLinux,
  }) : _runProcess = runProcess ?? Process.run,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux;

  final Directory _storeDirectory;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;
  final bool _isWindows;
  final bool _isMacOS;
  final bool _isLinux;

  /// The folder [open] reveals: `<store>/debug_logs/`.
  Directory get logDirectory =>
      Directory('${_storeDirectory.path}/$debugLogsDirectoryName');

  /// Creates the log folder when missing, then opens it in the
  /// file manager.
  ///
  /// Throws when the folder cannot be created or the file
  /// manager fails to open it (a non-zero exit on platforms
  /// whose exit code matters, or the process failing to start at
  /// all) — the caller surfaces the failure instead of the tap
  /// looking dead.
  Future<DebugLogFolderOpenOutcome> open() async {
    final dir = logDirectory;
    final command = fileManagerCommandFor(
      isWindows: _isWindows,
      isMacOS: _isMacOS,
      isLinux: _isLinux,
      directoryPath: dir.path,
    );
    if (command == null) return DebugLogFolderOpenOutcome.unsupported;
    await dir.create(recursive: true);
    final result = await _runProcess(command.executable, command.arguments);
    if (command.exitCodeMatters && result.exitCode != 0) {
      throw ProcessException(
        command.executable,
        command.arguments,
        'exited with code ${result.exitCode}',
        result.exitCode,
      );
    }
    return DebugLogFolderOpenOutcome.opened;
  }
}
