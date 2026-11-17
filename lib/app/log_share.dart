/// Debug log sharing (plan 46): hands the recorded debug logs to
/// the OS share sheet, so they can leave the device.
///
/// Until now the only way to get a log file out was the
/// LiveContainer container export. A directly sideloaded install
/// has no container access, so its logs were trapped on the
/// device — exactly the installs whose logs matter when a field
/// report needs evidence. The settings screen's share action is
/// the way out.
///
/// The native side is a hand-rolled platform channel, following
/// the project's established pattern (plan 35 replaced
/// wakelock_plus with a hand-rolled channel for the same reason):
/// a share_plus dependency would pull in a platform-interface
/// tree for one intent / view-controller presentation.
///
/// Only log files are ever shared. The collection below looks at
/// `debug_logs/*.log` and nothing else — registrations and other
/// documents-directory files never enter the list. The log
/// contents themselves are guaranteed free of credential material
/// and session keys by the diagnostics design
/// (core/diagnostics.dart) and the call-site audit in
/// test/debug_log_test.dart.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Subdirectory of the temporary directory the share staging
/// copies live in. The Android FileProvider paths file exposes
/// exactly this subdirectory of the cache dir — nothing else.
const String logShareStagingDirName = 'tmhb_log_share';

/// Lists the debug log files under `<documents>/debug_logs/`,
/// oldest first (file names are timestamps, so name order is
/// chronological). Only `.log` files count; anything else that
/// happens to sit in the directory is ignored. A missing
/// directory yields an empty list.
Future<List<File>> collectDebugLogFiles(Directory documentsDirectory) async {
  final dir = Directory('${documentsDirectory.path}/debug_logs');
  if (!await dir.exists()) return const [];
  final files = <File>[];
  await for (final entity in dir.list()) {
    if (entity is File && entity.path.endsWith('.log')) files.add(entity);
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Copies [files] into `<stagingParent>/tmhb_log_share/` and
/// returns the copies, in the same order.
///
/// Sharing works on copies, not the originals: the log rotation
/// may delete an original at any moment, and on Android the
/// FileProvider can only serve files under configured roots
/// (the cache dir is one; the documents directory is not).
/// Stale staged copies from a previous share are cleared first.
/// A source that vanishes mid-copy (rotation) is skipped.
Future<List<File>> stageDebugLogFiles(
  List<File> files,
  Directory stagingParent,
) async {
  final staging = Directory('${stagingParent.path}/$logShareStagingDirName');
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);
  final staged = <File>[];
  for (final file in files) {
    try {
      staged.add(
        await file.copy('${staging.path}/${file.path.split('/').last}'),
      );
    } on FileSystemException {
      // Rotation removed the source between listing and copying;
      // the remaining logs still share fine.
    }
  }
  return staged;
}

/// Outcome of a [DebugLogSharer.share] attempt.
enum DebugLogShareOutcome {
  /// The share sheet was presented with at least one log file.
  shared,

  /// No log files exist yet (debug mode never recorded, or all
  /// rotated away). The channel was not invoked.
  noLogs,

  /// This platform has no share-sheet channel (anything other
  /// than iOS / Android). The channel was not invoked.
  unsupported,
}

/// Collects, stages and shares the debug logs through the
/// platform channel `com.markun.tmhb/share_files`.
class DebugLogSharer {
  DebugLogSharer({
    required this._documentsDirectory,
    Future<Directory> Function()? stagingDirectory,
    MethodChannel? channel,
    bool? supported,
  }) : _stagingDirectory = stagingDirectory ?? getTemporaryDirectory,
       _channel = channel ?? const MethodChannel(_channelName),
       _supported = supported ?? (Platform.isIOS || Platform.isAndroid);

  static const String _channelName = 'com.markun.tmhb/share_files';

  final Directory _documentsDirectory;
  final Future<Directory> Function() _stagingDirectory;
  final MethodChannel _channel;
  final bool _supported;

  /// Shares the current log files. [origin] is the tapped
  /// widget's rect in global coordinates: iPad presents the
  /// share sheet as a popover and crashes without an anchor, so
  /// the UI passes its tile's rect; Android ignores it.
  Future<DebugLogShareOutcome> share({Rect? origin}) async {
    final files = await collectDebugLogFiles(_documentsDirectory);
    if (files.isEmpty) return DebugLogShareOutcome.noLogs;
    if (!_supported) return DebugLogShareOutcome.unsupported;
    final staged = await stageDebugLogFiles(files, await _stagingDirectory());
    if (staged.isEmpty) return DebugLogShareOutcome.noLogs;
    await _channel.invokeMethod<void>('shareFiles', {
      'paths': [for (final file in staged) file.path],
      if (origin != null) ...{
        'originX': origin.left,
        'originY': origin.top,
        'originWidth': origin.width,
        'originHeight': origin.height,
      },
    });
    return DebugLogShareOutcome.shared;
  }
}
