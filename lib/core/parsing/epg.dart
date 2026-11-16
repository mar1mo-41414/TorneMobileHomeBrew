/// Parsing of the `chEpg` binary payloads (plan 21).
///
/// Both `EPGGet` responses and `channelLogoDataGet` responses are
/// obfuscated with a single-byte XOR (0x9d) and carry zlib streams:
///
/// - EPG: one zlib stream whose plaintext is a sequence of service
///   blocks. Each block has an 18-byte header holding the service
///   triple (serviceId at +7, networkId at +12, transportStreamId
///   at +14, all big-endian), followed by EIT-style events:
///   `[eventId u16][start MJD u16][start BCD h/m/s][duration BCD
///   h/m/s][descriptorsLength u16][descriptors]`. Descriptors are
///   standard EIT: 0x4D short event, 0x4E extended event, 0x54
///   content. Text fields are ARIB STD-B24 (arib_b24.dart).
/// - Logos: a sequence of zlib streams, each decompressing to a
///   20-byte header + PNG. The header holds the decompressed
///   length (u16 BE at +2), the serviceId (u16 BE at +14) and the
///   PNG length (u16 BE at +18; 0 = no logo for that service).
///
/// All formats were determined by measurement against the real
/// device and the official clients (plan 21).
library;

import 'dart:io';
import 'dart:typed_data';

import '../arib_b24.dart';
import '../broadcast_text.dart';
import '../models/channel.dart';
import '../models/epg.dart';

/// The XOR key applied to every `chEpg` binary payload.
const int epgXorKey = 0x9d;

/// Removes the XOR obfuscation from a `chEpg` payload.
Uint8List deobfuscateEpgPayload(List<int> raw) {
  final out = Uint8List(raw.length);
  for (var i = 0; i < raw.length; i++) {
    out[i] = raw[i] ^ epgXorKey;
  }
  return out;
}

/// Inflates the (single) zlib stream of an EPG response body.
Uint8List inflateEpgResponse(List<int> rawResponse) {
  return Uint8List.fromList(
      ZLibDecoder().convert(deobfuscateEpgPayload(rawResponse)));
}

int _u16be(List<int> b, int off) => (b[off] << 8) | b[off + 1];

int _bcd(int b) => ((b >> 4) * 10) + (b & 0x0f);

/// MJD (Modified Julian Date) epoch: 1858-11-17.
final DateTime _mjdEpoch = DateTime.utc(1858, 11, 17);

/// Converts an EIT start (MJD + BCD time, JST wall clock) to an
/// absolute instant.
DateTime _eitStart(int mjd, int h, int m, int s) {
  final day = _mjdEpoch.add(Duration(days: mjd));
  return DateTime.utc(day.year, day.month, day.day, h, m, s)
      .subtract(const Duration(hours: 9));
}

/// One located service block in the EPG plaintext.
class _Block {
  const _Block(this.offset, this.channel);
  final int offset;
  final Channel channel;
}

/// Finds the service blocks in [plain]. Blocks are anchored on the
/// (networkId, transportStreamId) byte pair of a known channel with
/// the serviceId verified at the fixed header offset — six matched
/// bytes, which event data does not produce in practice (the full
/// live corpus walks cleanly, plan 21).
List<_Block> _findBlocks(Uint8List plain, List<Channel> channels) {
  final blocks = <_Block>[];
  for (final ch in channels) {
    final nid = ch.networkId, tsid = ch.transportStreamId;
    for (var i = 12; i + 4 <= plain.length; i++) {
      if (plain[i] == (nid >> 8) &&
          plain[i + 1] == (nid & 0xff) &&
          plain[i + 2] == (tsid >> 8) &&
          plain[i + 3] == (tsid & 0xff)) {
        final hp = i - 12;
        if (_u16be(plain, hp + 7) == ch.serviceId) {
          blocks.add(_Block(hp, ch));
        }
      }
    }
  }
  blocks.sort((a, b) => a.offset.compareTo(b.offset));
  // Dedupe identical offsets (a channel listed twice).
  final out = <_Block>[];
  for (final b in blocks) {
    if (out.isEmpty || out.last.offset != b.offset) out.add(b);
  }
  return out;
}

/// Parses the EPG plaintext into a guide. Services appear in
/// channel-list order; events in broadcast order.
EpgGuide parseEpgGuide(
  Uint8List plain,
  List<Channel> channels, {
  required int broadcastingType,
}) {
  final blocks = _findBlocks(plain, channels);
  final byService = <int, List<EpgEvent>>{};
  for (var i = 0; i < blocks.length; i++) {
    final start = blocks[i].offset + 18;
    final end = i + 1 < blocks.length ? blocks[i + 1].offset : plain.length;
    final events = _parseEvents(plain, start, end);
    if (events.isEmpty) continue;
    byService
        .putIfAbsent(blocks[i].channel.serviceId, () => [])
        .addAll(events);
  }
  final services = <EpgServiceGuide>[];
  for (final ch in channels) {
    final events = byService[ch.serviceId];
    if (events == null || events.isEmpty) continue;
    events.sort((a, b) => a.start.compareTo(b.start));
    services.add(EpgServiceGuide(channel: ch, events: events));
  }
  return EpgGuide(broadcastingType: broadcastingType, services: services);
}

List<EpgEvent> _parseEvents(Uint8List plain, int start, int end) {
  final events = <EpgEvent>[];
  var p = start;
  while (p + 12 <= end) {
    final eventId = _u16be(plain, p);
    final mjd = _u16be(plain, p + 2);
    final hh = _bcd(plain[p + 4]);
    final mm = _bcd(plain[p + 5]);
    final ss = _bcd(plain[p + 6]);
    final dh = _bcd(plain[p + 7]);
    final dm = _bcd(plain[p + 8]);
    final ds = _bcd(plain[p + 9]);
    final dlen = _u16be(plain, p + 10);
    if (p + 12 + dlen > end) break; // truncated tail: stop this block
    final fields = _parseDescriptors(plain, p + 12, p + 12 + dlen);
    events.add(EpgEvent(
      eventId: eventId,
      start: _eitStart(mjd, hh, mm, ss),
      duration: Duration(hours: dh, minutes: dm, seconds: ds),
      title: fields.title,
      shortText: fields.shortText,
      description: fields.description,
      cast: fields.cast,
      extendedItems: fields.items,
      extendedText: fields.extendedText,
      genreLevel1: fields.genreLevel1,
      genreLevel2: fields.genreLevel2,
    ));
    p += 12 + dlen;
  }
  return events;
}

class _EventFields {
  String? title;
  String? shortText;
  String? description;
  String? cast;
  String? extendedText;
  int? genreLevel1;
  int? genreLevel2;
  final items = <EpgExtendedItem>[];
}

String _text(List<int> bytes) =>
    normalizeBroadcastText(decodeAribB24(bytes));

_EventFields _parseDescriptors(Uint8List plain, int start, int end) {
  final fields = _EventFields();
  final extParts = <int, _ExtPart>{};
  var p = start;
  while (p + 2 <= end) {
    final tag = plain[p];
    final len = plain[p + 1];
    if (p + 2 + len > end) break;
    final body = plain.sublist(p + 2, p + 2 + len);
    switch (tag) {
      case 0x4d: // short_event_descriptor
        if (body.length >= 5 && _isJpn(body, 0)) {
          final nameLen = body[3];
          if (4 + nameLen <= body.length) {
            fields.title = _text(body.sublist(4, 4 + nameLen));
            final rest = body.sublist(4 + nameLen);
            if (rest.isNotEmpty) {
              final tl = rest[0];
              if (1 + tl <= rest.length) {
                fields.shortText = _text(rest.sublist(1, 1 + tl));
              }
            }
          }
        }
      case 0x4e: // extended_event_descriptor
        if (body.length >= 5 && _isJpn(body, 1)) {
          final number = body[0] >> 4;
          final part = _ExtPart();
          final loi = body[4];
          var ip = 5;
          final iend = 5 + loi;
          while (ip + 2 <= iend && ip + 2 <= body.length) {
            final dl = body[ip];
            if (ip + 1 + dl > body.length) break;
            final label = _text(body.sublist(ip + 1, ip + 1 + dl));
            ip += 1 + dl;
            if (ip >= body.length) break;
            final il = body[ip];
            if (ip + 1 + il > body.length) break;
            final value = _text(body.sublist(ip + 1, ip + 1 + il));
            ip += 1 + il;
            part.items.add(EpgExtendedItem(label: label, value: value));
          }
          if (ip < body.length) {
            final tl = body[ip];
            if (ip + 1 + tl <= body.length) {
              part.text = _text(body.sublist(ip + 1, ip + 1 + tl));
            }
          }
          extParts[number] = part;
        }
      case 0x54: // content_descriptor
        if (body.isNotEmpty) {
          fields.genreLevel1 = body[0] >> 4;
          fields.genreLevel2 = body[0] & 0x0f;
        }
    }
    p += 2 + len;
  }
  // Merge the extended parts in descriptor_number order; items
  // with the same label continue each other (split across parts).
  final numbers = extParts.keys.toList()..sort();
  final texts = <String>[];
  for (final n in numbers) {
    final part = extParts[n]!;
    for (final item in part.items) {
      if (fields.items.isNotEmpty && fields.items.last.label == item.label) {
        final last = fields.items.removeLast();
        fields.items.add(EpgExtendedItem(
            label: last.label, value: last.value + item.value));
      } else {
        fields.items.add(item);
      }
    }
    if (part.text != null && part.text!.isNotEmpty) texts.add(part.text!);
  }
  if (texts.isNotEmpty) fields.extendedText = texts.join();
  for (final item in fields.items) {
    if (item.label == '番組内容') {
      fields.description = item.value;
    } else if (item.label == '出演者') {
      fields.cast = item.value;
    }
  }
  fields.items.removeWhere(
      (i) => i.label == '番組内容' || i.label == '出演者');
  return fields;
}

bool _isJpn(List<int> body, int off) =>
    body.length >= off + 3 &&
    body[off] == 0x6a && // 'j'
    body[off + 1] == 0x70 && // 'p'
    body[off + 2] == 0x6e; // 'n'

class _ExtPart {
  final items = <EpgExtendedItem>[];
  String? text;
}

/// Adler-32 of [data] (the zlib stream trailer checksum).
int _adler32(List<int> data) {
  var a = 1;
  var b = 0;
  for (final byte in data) {
    a = (a + byte) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Inflates the first zlib stream in [bytes] starting at [start],
/// returning its decompressed bytes and compressed length.
///
/// The length cannot be found by trial conversion: dart:io's
/// ZLibDecoder silently returns partial output for truncated
/// input instead of throwing. Instead the stream end is located
/// through its Adler-32 trailer — the end position is where the
/// four trailer bytes equal the Adler-32 of the decompressed
/// content (verified by an exact re-decode of that prefix).
(List<int>, int) _inflateFirstStream(List<int> bytes, int start) {
  final decoder = ZLibDecoder();
  final full = decoder.convert(bytes.sublist(start));
  final adler = _adler32(full);
  final trailer = [
    (adler >> 24) & 0xff,
    (adler >> 16) & 0xff,
    (adler >> 8) & 0xff,
    adler & 0xff,
  ];
  for (var end = start + 6; end <= bytes.length; end++) {
    if (bytes[end - 4] == trailer[0] &&
        bytes[end - 3] == trailer[1] &&
        bytes[end - 2] == trailer[2] &&
        bytes[end - 1] == trailer[3]) {
      final check = decoder.convert(bytes.sublist(start, end));
      if (_listEquals(check, full)) {
        return (full, end - start);
      }
    }
  }
  throw const FormatException('zlib stream trailer not found');
}

/// Parses a `channelLogoDataGet` response into serviceId -> PNG
/// bytes. Records without a PNG (length field 0) are omitted, as
/// is the 8-byte file-header record.
Map<int, Uint8List> parseChannelLogos(List<int> rawResponse) {
  final data = deobfuscateEpgPayload(rawResponse);
  final logos = <int, Uint8List>{};
  var pos = 0;
  while (pos + 2 <= data.length) {
    if (data[pos] != 0x78) break; // not a zlib stream start
    final (List<int>, int) inflated;
    try {
      inflated = _inflateFirstStream(data, pos);
    } catch (_) {
      break; // truncated or corrupt tail: keep what we have
    }
    final (out, used) = inflated;
    if (used <= 0) break;
    pos += used;
    if (out.length < 20) continue; // file header record
    final declaredLen = _u16be(out, 2);
    if (declaredLen != out.length) continue;
    final serviceId = _u16be(out, 14);
    final pngLen = _u16be(out, 18);
    if (pngLen == 0 || 20 + pngLen > out.length) continue;
    final png = Uint8List.fromList(out.sublist(20, 20 + pngLen));
    if (png.length >= 4 && png[0] == 0x89 && png[1] == 0x50) {
      logos[serviceId] = png;
    }
  }
  return logos;
}
