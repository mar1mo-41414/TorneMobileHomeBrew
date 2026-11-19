/// File picking tests (plan 84): the picked file's bytes come
/// back, cancellation and other empty outcomes read as null
/// (a normal path, not an error), and a platform failure
/// propagates to the caller instead of being swallowed — the
/// plan 69.5 leftover, where a picker exception left the
/// button looking dead.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/file_pick.dart';

void main() {
  group('FileBytesPicker', () {
    test('returns the bytes of the picked file', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final picker = FileBytesPicker(
        pickFiles: () async => FilePickerResult([
          PlatformFile(name: 'credentials.env', size: 3, bytes: bytes),
        ]),
      );
      expect(await picker.pick(), bytes);
    });

    test('returns null when the user cancels', () async {
      final picker = FileBytesPicker(pickFiles: () async => null);
      expect(await picker.pick(), isNull);
    });

    test('returns null when the result carries no file', () async {
      final picker = FileBytesPicker(
        pickFiles: () async => const FilePickerResult([]),
      );
      expect(await picker.pick(), isNull);
    });

    test('returns null when the picked file has no bytes loaded', () async {
      final picker = FileBytesPicker(
        pickFiles: () async => FilePickerResult([
          PlatformFile(name: 'cert.bin', size: 88),
        ]),
      );
      expect(await picker.pick(), isNull);
    });

    test('propagates a platform exception to the caller', () async {
      final picker = FileBytesPicker(
        pickFiles: () async =>
            throw PlatformException(code: 'ENTITLEMENT_NOT_FOUND'),
      );
      await expectLater(
        picker.pick(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'ENTITLEMENT_NOT_FOUND',
          ),
        ),
      );
    });
  });
}
