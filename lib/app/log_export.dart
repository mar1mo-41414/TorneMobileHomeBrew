/// Writing the debug logs into the public Downloads folder
/// (plan 142).
///
/// Log sharing (plan 46) rides the OS share sheet, but on
/// Android TV the sheet offers almost no destinations: on the
/// Fire TV checked in plan 140 the only candidates were a
/// Taildrop (which needs the device's tailnet connection and
/// failed there) and one unknown app — no save-to-storage
/// target at all, so the recorded logs stayed trapped in the
/// app's private store, exactly the situation plan 46 set out
/// to fix. The TV edition therefore gets a second way out:
/// write the log files into `Downloads/tmhb-log/`, a place a
/// USB cable, adb or a file manager can reach without any
/// account or network state.
///
/// The platform half follows the Downloads scan (plan 127):
/// the same method channel carries the files to MainActivity,
/// which knows how the public Downloads folder is resolved
/// and what each Android generation allows there (direct
/// writes under the legacy storage model, MediaStore under
/// scoped storage).
///
/// Only the recorded debug logs are ever exported — the
/// collection is the same one sharing uses
/// (`debug_logs/*.log`, see log_share.dart) — and every export
/// writes fresh file names stamped with the export time, so
/// re-exporting after another session never overwrites the
/// files an earlier export left behind.
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'log_share.dart';

/// The subdirectory of the public Downloads folder the
/// exported logs land in.
const String logExportDirectoryName = 'tmhb-log';

/// The file name an exported copy of the log file named
/// [sourceName] gets when exported at [exportedAt]:
/// `<yyyyMMdd-HHmmss-mmm>_<sourceName>`. The stamp leads, so
/// the folder sorts by export, and its millisecond precision
/// (the same convention as the log file names themselves,
/// see debug_log.dart) keeps two exports of the same file
/// from colliding.
String exportedLogFileName(DateTime exportedAt, String sourceName) {
  String two(int v) => v.toString().padLeft(2, '0');
  final ms = exportedAt.millisecond.toString().padLeft(3, '0');
  return '${exportedAt.year}${two(exportedAt.month)}${two(exportedAt.day)}-'
      '${two(exportedAt.hour)}${two(exportedAt.minute)}'
      '${two(exportedAt.second)}-$ms'
      '_$sourceName';
}

/// One log file handed to the platform side for export.
class LogExportFile {
  const LogExportFile({required this.name, required this.bytes});

  /// The name the copy lands under in `Downloads/tmhb-log/`.
  final String name;

  /// The log file's contents, byte for byte.
  final Uint8List bytes;
}

/// The platform call behind [DebugLogDownloadsExporter]:
/// writes [files] into `Downloads/tmhb-log/` and returns the
/// folder the files landed in (its absolute path under the
/// legacy storage model, its public relative form under
/// scoped storage), for the diagnostics record.
typedef PlatformExportLogs = Future<String?> Function(
  List<LogExportFile> files,
);

/// Outcome of a [DebugLogDownloadsExporter.export] attempt.
enum DebugLogExportOutcome {
  /// At least one log file was written to Downloads.
  exported,

  /// No log files exist yet (debug mode never recorded, or
  /// all rotated away). The channel was not invoked.
  noLogs,

  /// This platform has no Downloads export (anything other
  /// than Android). The channel was not invoked.
  unsupported,
}

/// The result of an export attempt: the outcome, how many
/// files were written (0 unless the outcome is
/// [DebugLogExportOutcome.exported]) and where they went
/// (the folder the platform side reported, when it did).
class DebugLogExportResult {
  const DebugLogExportResult({
    required this.outcome,
    this.fileCount = 0,
    this.directoryPath,
  });

  final DebugLogExportOutcome outcome;
  final int fileCount;
  final String? directoryPath;
}

/// Exports the recorded debug logs into `Downloads/tmhb-log/`
/// through the platform channel
/// `com.markun.tmhb/credential_downloads` — the Downloads
/// channel of plan 127; a second folder convention does not
/// warrant a channel of its own.
class DebugLogDownloadsExporter {
  DebugLogDownloadsExporter({
    required this._storeDirectory,
    PlatformExportLogs? platformExport,
    bool? supported,
    DateTime Function()? now,
  }) : _platformExport = platformExport ?? _platformExportLogs,
       _supported = supported ?? Platform.isAndroid,
       _now = now ?? DateTime.now;

  static const MethodChannel _channel = MethodChannel(
    'com.markun.tmhb/credential_downloads',
  );

  final Directory _storeDirectory;
  final PlatformExportLogs _platformExport;
  final bool _supported;
  final DateTime Function() _now;

  static Future<String?> _platformExportLogs(List<LogExportFile> files) {
    return _channel.invokeMethod<String>('exportLogsToDownloads', {
      'files': [
        for (final file in files) {'name': file.name, 'bytes': file.bytes},
      ],
    });
  }

  /// Exports the current log files.
  ///
  /// Platform failures propagate as the platform threw them —
  /// a PlatformException, with code `permission_denied` when
  /// the folder cannot be written — and the caller turns them
  /// into a visible error and a diagnostics record instead of
  /// swallowing them, the same split as the Downloads scan
  /// (plan 127).
  Future<DebugLogExportResult> export() async {
    final files = await collectDebugLogFiles(_storeDirectory);
    if (files.isEmpty) {
      return const DebugLogExportResult(outcome: DebugLogExportOutcome.noLogs);
    }
    if (!_supported) {
      return const DebugLogExportResult(
        outcome: DebugLogExportOutcome.unsupported,
      );
    }
    final exportedAt = _now();
    final payload = <LogExportFile>[];
    for (final file in files) {
      try {
        payload.add(
          LogExportFile(
            name: exportedLogFileName(exportedAt, file.path.split('/').last),
            bytes: await file.readAsBytes(),
          ),
        );
      } on FileSystemException {
        // Rotation removed the source between listing and
        // reading; the remaining logs still export fine (the
        // same tolerance as the share staging).
      }
    }
    if (payload.isEmpty) {
      return const DebugLogExportResult(outcome: DebugLogExportOutcome.noLogs);
    }
    final directoryPath = await _platformExport(payload);
    return DebugLogExportResult(
      outcome: DebugLogExportOutcome.exported,
      fileCount: payload.length,
      directoryPath: directoryPath,
    );
  }
}
