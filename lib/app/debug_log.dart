/// Debug mode (plan 28): user-toggleable diagnostics logging.
///
/// When the master switch (settings screen) is on, the [DiagLog]
/// built by `diagLogProvider` (app/providers.dart) writes
/// category-tagged records to files in the app store
/// directory, so the user can pull them off the device and hand
/// them over. When off (the default), nothing is recorded
/// anywhere.
///
/// Records contain stage transitions, error classifications,
/// HTTP statuses, AKE response codes, byte counts and durations
/// ONLY. Credential material and session keys are never logged —
/// see the hard rule in core/diagnostics.dart.
library;

import 'dart:async';
import 'dart:io';

import '../core/core.dart';
import 'bootstrap.dart';

/// Debug mode settings: the master switch and the enabled
/// category set. Persisted in the key-value store by
/// DebugSettingsNotifier (app/providers.dart).
class DebugSettings {
  const DebugSettings({
    this.master = false,
    this.categories = const {
      DiagCategory.ake,
      DiagCategory.playback,
      DiagCategory.network,
      DiagCategory.epg,
      DiagCategory.discovery,
      DiagCategory.ui,
    },
  });

  final bool master;
  final Set<DiagCategory> categories;

  DebugSettings copyWith({bool? master, Set<DiagCategory>? categories}) =>
      DebugSettings(
        master: master ?? this.master,
        categories: categories ?? this.categories,
      );

  /// Serializes the category set for the key-value store.
  String encodeCategories() => categories.map((c) => c.name).join(',');

  /// Parses a stored category set; null or empty means the
  /// default (all categories).
  static Set<DiagCategory> decodeCategories(String? raw) {
    if (raw == null || raw.isEmpty) return const DebugSettings().categories;
    final parsed = <DiagCategory>{};
    for (final name in raw.split(',')) {
      for (final category in DiagCategory.values) {
        if (category.name == name.trim()) parsed.add(category);
      }
    }
    return parsed;
  }
}

/// User-facing label per diagnostics category (settings screen).
String diagCategoryLabel(DiagCategory category) => switch (category) {
  DiagCategory.ake => 'AKE (DTCP 認証)',
  DiagCategory.playback => '再生',
  DiagCategory.network => 'ネットワーク',
  DiagCategory.epg => '番組表',
  DiagCategory.discovery => '機器の発見',
  DiagCategory.ui => 'UI',
};

/// Appends diagnostics lines to timestamped files under
/// `<store>/debug_logs/`, with rotation so an always-on debug
/// mode cannot grow without bound: at most [maxFiles] files and
/// [maxTotalBytes] in total; a single file rolls at [maxFileBytes].
class FileDebugLogSink {
  FileDebugLogSink(
    this._storeDirectory, {
    this.maxFiles = 5,
    this.maxTotalBytes = 2 * 1024 * 1024,
    this.maxFileBytes = 512 * 1024,
  });

  final Directory _storeDirectory;
  final int maxFiles;
  final int maxTotalBytes;
  final int maxFileBytes;

  Directory get _logDirectory =>
      Directory('${_storeDirectory.path}/$debugLogsDirectoryName');

  /// The directory the log files live in (shown in settings).
  String get logDirectoryPath => _logDirectory.path;

  File? _current;
  int _currentBytes = 0;
  Future<void> _chain = Future<void>.value();

  /// Queues one record. Writes are serialized and best-effort:
  /// a logging failure never breaks the feature being logged.
  void write(DiagCategory category, String message) {
    final line =
        '${DateTime.now().toIso8601String()} [${category.name}] $message\n';
    _chain = _chain.then((_) => _append(line)).catchError((_) {});
  }

  /// Waits until all queued records are on disk (tests).
  Future<void> flush() => _chain;

  Future<void> _append(String line) async {
    final dir = _logDirectory;
    await dir.create(recursive: true);
    if (_current == null || _currentBytes >= maxFileBytes) {
      _current = File('${dir.path}/${_fileName(DateTime.now())}');
      _currentBytes = 0;
      await _prune(dir);
    }
    await _current!.writeAsString(line, mode: FileMode.append);
    _currentBytes += line.length;
  }

  Future<void> _prune(Directory dir) async {
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.log')) files.add(entity);
    }
    final stats = <File, FileStat>{};
    var total = 0;
    for (final file in files) {
      final stat = await file.stat();
      stats[file] = stat;
      total += stat.size;
    }
    files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
    // Delete oldest first until one more (incoming) file stays
    // within both caps. All listed files are complete — the file
    // about to be written is not on disk yet — so any of them may
    // be deleted.
    while (files.isNotEmpty &&
        (files.length >= maxFiles || total + maxFileBytes > maxTotalBytes)) {
      final victim = files.removeAt(0);
      total -= stats[victim]!.size;
      await victim.delete();
    }
  }

  static String _fileName(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final ms = t.millisecond.toString().padLeft(3, '0');
    return 'tmhb-debug-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}-$ms.log';
  }
}
