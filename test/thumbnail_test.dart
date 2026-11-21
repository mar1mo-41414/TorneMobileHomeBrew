/// Plan 86.6 (#6): defensive extraction of a thumbnail image
/// from the thumbnailMapGet binary payload by magic bytes.
/// Plan 99: the map's entry count, and the decode of the
/// real payload format — AES-128-CBC (app-common key, zero
/// IV) over a 360x240 UYVY frame, served as a BMP.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';
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

  group('thumbnailEntryCount', () {
    List<int> map(int count, {int? bytes}) {
      final out = <int>[
        (count >> 24) & 0xFF,
        (count >> 16) & 0xFF,
        (count >> 8) & 0xFF,
        count & 0xFF,
      ];
      for (var i = 0; i < count; i++) {
        out.addAll([0x00, 0x00, 0x0A, 0x00]);
      }
      return bytes == null ? out : out.sublist(0, bytes);
    }

    test('reads the big-endian count', () {
      expect(thumbnailEntryCount(map(3)), 3);
      expect(thumbnailEntryCount(map(0)), 0);
      expect(thumbnailEntryCount(map(242)), 242);
    });

    test('rejects truncated or absurd payloads', () {
      expect(thumbnailEntryCount(map(3, bytes: 8)), isNull);
      expect(thumbnailEntryCount(const []), isNull);
      expect(thumbnailEntryCount(const [0xFF, 0xFF, 0xFF, 0xFF]), isNull);
    });
  });

  group('decodeThumbnailPayload', () {
    // The key is duplicated here on purpose: the fixture is
    // encrypted with the plan 99 app-common key so the test
    // fails if the production key ever drifts from it.
    const key = [
      0x33,
      0xa4,
      0x9d,
      0x7b,
      0x3d,
      0x0f,
      0x35,
      0x84,
      0x70,
      0x27,
      0x91,
      0x7d,
      0x64,
      0x17,
      0xdb,
      0x54,
    ];

    Uint8List encrypt(Uint8List plain) {
      final cipher = CBCBlockCipher(AESEngine())
        ..init(
          true,
          ParametersWithIV(
            KeyParameter(Uint8List.fromList(key)),
            Uint8List(16),
          ),
        );
      final out = Uint8List(plain.length);
      for (var off = 0; off < plain.length; off += 16) {
        cipher.processBlock(plain, off, out, off);
      }
      return out;
    }

    /// One UYVY frame filled with a single (U, Y, V) triple.
    Uint8List solidFrame(int u, int y, int v) {
      final frame = Uint8List(thumbnailPayloadSize);
      for (var i = 0; i < frame.length; i += 4) {
        frame[i] = u;
        frame[i + 1] = y;
        frame[i + 2] = v;
        frame[i + 3] = y;
      }
      return frame;
    }

    test('rejects payloads that are not exactly one frame', () {
      expect(decodeThumbnailPayload(const []), isNull);
      expect(decodeThumbnailPayload(List.filled(172799, 0)), isNull);
      expect(decodeThumbnailPayload(List.filled(172801, 0)), isNull);
    });

    test('a neutral frame decodes to a grey BMP', () {
      final bmp = decodeThumbnailPayload(encrypt(solidFrame(128, 128, 128)))!;
      expect(bmp.length, 54 + 360 * 240 * 3);
      expect(bmp[0], 0x42); // 'B'
      expect(bmp[1], 0x4D); // 'M'
      final head = ByteData.sublistView(bmp);
      expect(head.getInt32(18, Endian.little), 360);
      expect(head.getInt32(22, Endian.little), 240);
      expect(head.getUint16(28, Endian.little), 24);
      // Every pixel is (128, 128, 128) in BGR byte order.
      for (var i = 54; i < bmp.length; i++) {
        expect(bmp[i], 128);
      }
    });

    test('chrominance follows the BT.601 full-range conversion', () {
      // U=90, Y=76, V=255 -> R=254, G=0 (clamped), B=9.
      final bmp = decodeThumbnailPayload(encrypt(solidFrame(90, 76, 255)))!;
      expect(bmp[54], 9); // B
      expect(bmp[55], 0); // G
      expect(bmp[56], 254); // R
      // The second pixel of the pair shares the chroma.
      expect(bmp[57], 9);
      expect(bmp[58], 0);
      expect(bmp[59], 254);
    });
  });
}
