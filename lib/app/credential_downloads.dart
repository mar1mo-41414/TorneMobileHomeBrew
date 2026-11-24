/// Scanning the device Downloads folder for credential files
/// (plan 127).
///
/// Android TV has no usable file picker, so the credential
/// import screen can instead look in the one place a file can be
/// dropped without any tooling: the Downloads folder. The
/// platform half lives behind this seam (the same separation as
/// the file picker in plan 84): the Android side lists the
/// folder, reads the files whose names follow the
/// `credentials*.env` shape, and hands the bytes over; deciding
/// which of them can actually be imported is Dart-side work
/// (core/dtcp/credential_candidates.dart).
///
/// The folder goes by two spellings in the field (plan 132):
/// the system Downloads directory and a plural "Downloads"
/// sibling can both exist, so the platform side scans both and
/// reports each file's path; the same file seen from both
/// spellings collapses to one entry here, by path.
///
/// Failures propagate to the caller as the platform threw them —
/// a PlatformException, with code `permission_denied` when the
/// folder cannot be read — and the caller turns them into a
/// visible error and a diagnostics record instead of swallowing
/// them, the same split as plan 84.
library;

import 'package:flutter/services.dart';

/// One file found by the platform scan: base name and contents.
class DownloadsScannedFile {
  const DownloadsScannedFile({
    required this.name,
    required this.bytes,
    this.path,
  });

  final String name;
  final Uint8List bytes;

  /// The file's full path on the device, when the platform
  /// reported one (metadata only; never displayed). Two scanned
  /// files that share a path are the same file seen from two
  /// folders; two that share only a name are not.
  final String? path;
}

/// The platform scan call behind [CredentialDownloadsScanner]:
/// the files found, in no particular order.
typedef PlatformScanDownloads = Future<List<DownloadsScannedFile>> Function();

/// Scans the Downloads folder for credential-file candidates.
class CredentialDownloadsScanner {
  CredentialDownloadsScanner({PlatformScanDownloads? scanDownloads})
    : _scanDownloads = scanDownloads ?? _platformScan;

  final PlatformScanDownloads _scanDownloads;

  static const MethodChannel _channel = MethodChannel(
    'com.markun.tmhb/credential_downloads',
  );

  static Future<List<DownloadsScannedFile>> _platformScan() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('scanDownloads');
    if (raw == null) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          DownloadsScannedFile(
            name: entry['name'] as String,
            bytes: entry['bytes'] as Uint8List,
            path: entry['path'] as String?,
          ),
    ];
  }

  /// The candidate-shaped files currently in Downloads. Throws
  /// whatever the platform side throws (see the library comment).
  ///
  /// Sightings that carry the same path are one file seen from
  /// more than one scanned folder (plan 132) and collapse to
  /// the first sighting. Files without a path cannot be told
  /// apart that way and always pass through.
  Future<List<DownloadsScannedFile>> scan() async {
    final files = await _scanDownloads();
    final seenPaths = <String>{};
    return [
      for (final file in files)
        if (file.path == null || seenPaths.add(file.path!)) file,
    ];
  }
}
