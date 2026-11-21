/// Thumbnail payload extraction (plan 86.6).
///
/// The image is located by its magic bytes: the earliest
/// complete JPEG or PNG embedded in the payload wins.
/// Anything else — an empty payload, an unknown container,
/// a truncated embedded image — yields null and the UI
/// keeps its placeholder.
///
/// Real-unit measurement (plan 97) settled what the unit
/// actually serves: `recorded/thumbnailMapGet` answers with
/// a position map — a big-endian uint32 count followed by
/// that many uint32 values, roughly one entry per 15
/// seconds of recording — and contains no image at all.
/// The frames live behind `recorded/recordedContentThumbnailGet`
/// (`id` + a `thumbnailEntryId` index) as fixed-size
/// 172,800-byte payloads, the size of a raw 320x180 RGB
/// frame, but the bytes are encrypted (full entropy, no
/// repeated 16-byte blocks, no short XOR period), so they
/// cannot be rendered without the official client's
/// decryption scheme. On a real unit this extractor is
/// therefore expected to find nothing; it stays as the
/// defensive path if a unit ever embeds an image.
library;

import 'dart:typed_data';

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
