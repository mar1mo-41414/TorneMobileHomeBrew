/// Picking one file's bytes through the platform file picker
/// (plan 84).
///
/// The credential import screen (plan 67) reads the picked file
/// from memory, so the pick runs with data loading enabled. The
/// picker used to be called bare from the screen: when the
/// platform side failed — the missing-entitlement error on macOS
/// in plan 69 is the measured case — the PlatformException
/// escaped as an unhandled async error and the button simply
/// looked dead. The entitlement half was fixed in plan 69; this
/// is the Dart-side half left over in plan 69.5: the platform
/// call sits behind an injectable seam (the same separation as
/// the log folder opener in plan 71), and failures propagate to
/// the caller, which turns them into a visible error and a
/// diagnostics record instead of swallowing them.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The platform pick call behind [FileBytesPicker]: the raw
/// picker result, or null when the user cancelled.
typedef PlatformPickFiles = Future<FilePickerResult?> Function();

/// Picks a single file and hands back its bytes.
class FileBytesPicker {
  FileBytesPicker({PlatformPickFiles? pickFiles})
    : _pickFiles = pickFiles ?? _platformPick;

  final PlatformPickFiles _pickFiles;

  static Future<FilePickerResult?> _platformPick() =>
      FilePicker.platform.pickFiles(withData: true);

  /// The picked file's bytes, or null when nothing was picked:
  /// the user cancelled, the result carried no file, or the
  /// file's bytes were not loaded. Cancellation is a normal
  /// outcome, never an error.
  ///
  /// Throws whatever the platform picker throws (a
  /// PlatformException in the measured cases). The failure is
  /// deliberately not converted here — surfacing it is the
  /// caller's job, the same split as plan 71.
  Future<Uint8List?> pick() async {
    final result = await _pickFiles();
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.bytes;
  }
}
