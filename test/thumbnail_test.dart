/// Plan 86.6 (#6): defensive extraction of a thumbnail image
/// from the thumbnailMapGet binary payload by magic bytes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/parsing/thumbnail.dart';

List<int> _jpeg({int pad = 64}) => [
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  ...List.filled(pad, 0x11),
  0xFF,
  0xD9,
];

List<int> _png() => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR header
  ...List.filled(13, 0x22),
  0x00, 0x00, 0x00, 0x00, // IEND length
  0x49, 0x45, 0x4E, 0x44, // IEND
  0xAE, 0x42, 0x60, 0x82, // CRC
];

void main() {
  group('extractThumbnailImage', () {
    test('a bare JPEG payload is returned whole', () {
      final payload = _jpeg();
      expect(extractThumbnailImage(payload), payload);
    });

    test('a bare PNG payload is returned whole', () {
      final payload = _png();
      expect(extractThumbnailImage(payload), payload);
    });

    test('a JPEG embedded behind a container header is extracted', () {
      final jpeg = _jpeg();
      final payload = [
        ...List.filled(16, 0x00),
        ...jpeg,
        ...List.filled(8, 0x7F),
      ];
      expect(extractThumbnailImage(payload), jpeg);
    });

    test('a PNG embedded behind a container header is extracted', () {
      final png = _png();
      final payload = [
        ...List.filled(4, 0x03),
        ...png,
        ...List.filled(4, 0x00),
      ];
      expect(extractThumbnailImage(payload), png);
    });

    test('the earliest image wins when both kinds are present', () {
      final png = _png();
      final payload = [...png, ..._jpeg()];
      expect(extractThumbnailImage(payload), png);
    });

    test('empty and image-free payloads yield null', () {
      expect(extractThumbnailImage(const []), isNull);
      expect(extractThumbnailImage(List.filled(128, 0x00)), isNull);
      expect(extractThumbnailImage('not an image'.codeUnits), isNull);
    });

    test('an embedded JPEG without an end marker yields null', () {
      final payload = [
        ...List.filled(8, 0x00),
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        ...List.filled(32, 0x11),
      ];
      expect(extractThumbnailImage(payload), isNull);
    });

    test('an embedded PNG without IEND yields null', () {
      final payload = [
        ...List.filled(8, 0x00),
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        ...List.filled(32, 0x22),
      ];
      expect(extractThumbnailImage(payload), isNull);
    });
  });
}
