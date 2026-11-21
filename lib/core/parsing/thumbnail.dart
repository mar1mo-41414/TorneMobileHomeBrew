/// Thumbnail payload handling (plan 86.6, plan 99).
///
/// What the unit serves (measured, plan 97 / 99):
/// `recorded/thumbnailMapGet` answers with a position map —
/// a big-endian uint32 count followed by that many uint32
/// values, roughly one entry per 15 seconds of recording —
/// and contains no image at all. The frames live behind
/// `recorded/recordedContentThumbnailGet` (`id` + a
/// `thumbnailEntryId` index) as fixed-size 172,800-byte
/// payloads.
///
/// Plan 99 settled what those payloads are. They are
/// AES-128-CBC ciphertext (that part of the plan 97 verdict
/// held: full entropy, no repeated 16-byte blocks, no short
/// XOR period, no raw pixel layout fits). The key, however,
/// is not per-title or per-unit: the official client's
/// `decryptThumbnailNasne` takes no key argument and reads
/// two file-embedded globals — the key below and an
/// all-zero IV — so every unit's thumbnails decrypt with
/// the same app-common constant. The plaintext is a
/// 360x240 UYVY (YUV 4:2:2) frame: 360 * 240 * 2 = 172,800
/// bytes. Decrypted frames were matched against the same
/// recordings streamed over DTCP-IP (correlation 0.74–0.90
/// at the expected ~15-second positions), so the format is
/// confirmed, and plan 97's "cannot be rendered" conclusion
/// is corrected: the frames render fine once decrypted.
///
/// [decodeThumbnailPayload] performs that decryption and
/// converts UYVY to a 24-bit BMP the image widgets can
/// consume directly. [extractThumbnailImage] stays as the
/// defensive path if a unit ever embeds a plain image.
library;

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Frame geometry of a `recordedContentThumbnailGet`
/// payload (plan 99).
const thumbnailWidth = 360;
const thumbnailHeight = 240;
const thumbnailPayloadSize = thumbnailWidth * thumbnailHeight * 2;

/// The thumbnail cipher key (plan 99): an app-common
/// constant the official client carries as an initialized
/// global, used with an all-zero IV. It is not derived from
/// any pairing or per-unit credential.
const _thumbnailKey = [
  0x33, 0xa4, 0x9d, 0x7b, 0x3d, 0x0f, 0x35, 0x84, //
  0x70, 0x27, 0x91, 0x7d, 0x64, 0x17, 0xdb, 0x54,
];

/// The entry count of a `thumbnailMapGet` payload: the
/// big-endian uint32 at offset 0, with one uint32 position
/// per entry after it. Returns null when the payload is too
/// short to hold the entries it declares.
int? thumbnailEntryCount(List<int> mapPayload) {
  if (mapPayload.length < 4) return null;
  final count = ByteData.sublistView(
    mapPayload is Uint8List ? mapPayload : Uint8List.fromList(mapPayload),
  ).getUint32(0, Endian.big);
  if (count > 0x100000) return null;
  if (mapPayload.length < 4 + 4 * count) return null;
  return count;
}

/// Decrypts a `recordedContentThumbnailGet` payload
/// (AES-128-CBC, app-common key, zero IV) and converts the
/// 360x240 UYVY plaintext to a 24-bit BMP. Returns null for
/// any payload that is not exactly one frame.
Uint8List? decodeThumbnailPayload(List<int> payload) {
  if (payload.length != thumbnailPayloadSize) return null;
  final cipher = CBCBlockCipher(AESEngine())
    ..init(
      false,
      ParametersWithIV(
        KeyParameter(Uint8List.fromList(_thumbnailKey)),
        Uint8List(16),
      ),
    );
  final input = payload is Uint8List ? payload : Uint8List.fromList(payload);
  final plain = Uint8List(thumbnailPayloadSize);
  for (var off = 0; off < thumbnailPayloadSize; off += 16) {
    cipher.processBlock(input, off, plain, off);
  }
  return _uyvyToBmp(plain);
}

/// UYVY (packed YUV 4:2:2, chroma shared per pixel pair)
/// to 24-bit BMP. Colour conversion is BT.601 full-range —
/// the conversion the plan 99 verification renders used.
Uint8List _uyvyToBmp(Uint8List uyvy) {
  const rowBytes = thumbnailWidth * 3;
  const imageBytes = rowBytes * thumbnailHeight;
  const headerBytes = 54;
  final bmp = Uint8List(headerBytes + imageBytes);
  final head = ByteData.sublistView(bmp);
  bmp[0] = 0x42; // 'B'
  bmp[1] = 0x4D; // 'M'
  head.setUint32(2, bmp.length, Endian.little);
  head.setUint32(10, headerBytes, Endian.little);
  head.setUint32(14, 40, Endian.little); // BITMAPINFOHEADER
  head.setInt32(18, thumbnailWidth, Endian.little);
  head.setInt32(22, thumbnailHeight, Endian.little); // bottom-up
  head.setUint16(26, 1, Endian.little); // planes
  head.setUint16(28, 24, Endian.little); // bpp
  head.setUint32(34, imageBytes, Endian.little);
  for (var y = 0; y < thumbnailHeight; y++) {
    // BMP rows are stored bottom-up.
    final srcRow = (thumbnailHeight - 1 - y) * thumbnailWidth * 2;
    var dst = headerBytes + y * rowBytes;
    for (var x = 0; x < thumbnailWidth; x += 2) {
      final src = srcRow + x * 2;
      final u = uyvy[src] - 128;
      final v = uyvy[src + 2] - 128;
      for (var k = 0; k < 2; k++) {
        final luma = uyvy[src + 1 + 2 * k];
        final r = (luma + 1.402 * v).round();
        final g = (luma - 0.344136 * u - 0.714136 * v).round();
        final b = (luma + 1.772 * u).round();
        bmp[dst++] = b.clamp(0, 255);
        bmp[dst++] = g.clamp(0, 255);
        bmp[dst++] = r.clamp(0, 255);
      }
    }
  }
  return bmp;
}

/// Extracts the first complete JPEG or PNG image embedded in
/// [payload], or the payload itself when it is a bare image.
/// Returns null when no complete image is present.
Uint8List? extractThumbnailImage(List<int> payload) {
  final jpeg = _jpegSpan(payload);
  final png = _pngSpan(payload);
  if (jpeg == null) return png == null ? null : _slice(payload, png);
  if (png == null) return _slice(payload, jpeg);
  return _slice(payload, jpeg.$1 <= png.$1 ? jpeg : png);
}

Uint8List _slice(List<int> payload, (int, int) span) =>
    Uint8List.fromList(payload.sublist(span.$1, span.$2));

/// (start, end) of a JPEG: SOI (FF D8 FF) through EOI (FF D9).
/// A payload that *is* a JPEG (SOI at offset 0) is accepted
/// whole even without a visible EOI — the image widget rejects
/// undecodable bytes on its own. An embedded SOI without an
/// EOI is treated as no image: inside a container it is more
/// likely a false positive than a truncated thumbnail.
(int, int)? _jpegSpan(List<int> payload) {
  for (var i = 0; i + 2 < payload.length; i++) {
    if (payload[i] == 0xFF &&
        payload[i + 1] == 0xD8 &&
        payload[i + 2] == 0xFF) {
      for (var j = i + 3; j + 1 < payload.length; j++) {
        if (payload[j] == 0xFF && payload[j + 1] == 0xD9) {
          return (i, j + 2);
        }
      }
      return i == 0 ? (0, payload.length) : null;
    }
  }
  return null;
}

/// (start, end) of a PNG: the 8-byte signature through the
/// IEND chunk (type + CRC included in the span).
(int, int)? _pngSpan(List<int> payload) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i + signature.length <= payload.length; i++) {
    var matches = true;
    for (var k = 0; k < signature.length; k++) {
      if (payload[i + k] != signature[k]) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    // 'IEND' chunk type bytes; the chunk is length(0) + type +
    // CRC, so the image ends 8 bytes after the type starts.
    for (var j = i + signature.length; j + 3 < payload.length; j++) {
      if (payload[j] == 0x49 &&
          payload[j + 1] == 0x45 &&
          payload[j + 2] == 0x4E &&
          payload[j + 3] == 0x44) {
        final end = j + 8;
        return (i, end <= payload.length ? end : payload.length);
      }
    }
    return i == 0 ? (0, payload.length) : null;
  }
  return null;
}
