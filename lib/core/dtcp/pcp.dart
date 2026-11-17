/// PCP (Protected Content Packet) decryption.
///
/// Port of pydtcpip's `dtcp/pcp.py` (MIT, (c) tsukumijima). A PCP
/// packet is a 14-byte header followed by AES-128-CBC ciphertext
/// padded to a 16-byte multiple; the header's content length is the
/// authoritative plaintext length.
///
/// Plan 30: decryption is STREAMING. The reference frames whole
/// packets before decrypting, which on a fast LAN hides the wait —
/// but the real packets are 1 MiB, and over a slow path (VPN from
/// outside) one packet took ~8.5 s to arrive while the player,
/// having received nothing at all, gave up after ~5 s. CBC
/// decryption needs only the previous ciphertext block, so each
/// 16-byte block is decrypted and emitted as soon as it arrives;
/// only the sub-block tail and the header are ever buffered.
library;

import 'dart:math';
import 'dart:typed_data';

import '../errors.dart';
import 'dtcp_crypto.dart';

class PcpHeader {
  PcpHeader._({
    required this.encryptionMode,
    required this.exchangeKeyLabel,
    required this.nonce,
    required this.contentLength,
  });

  /// E-EMI (content encryption mode indicator), header byte 0 low
  /// nibble.
  final int encryptionMode;

  /// Exchange key label, header byte 1.
  final int exchangeKeyLabel;

  /// 8-byte nonce, header bytes 2..9.
  final Uint8List nonce;

  /// Plaintext length in bytes, header bytes 10..13 (big-endian).
  final int contentLength;

  static const int size = 14;

  static PcpHeader parse(List<int> data) {
    if (data.length < size) {
      throw NasneError.parse('dtcp:pcp', cause: 'PCP header is too short');
    }
    if ((data[0] >> 6) != 0 || ((data[0] >> 4) & 0x3) != 0) {
      throw NasneError.parse(
        'dtcp:pcp',
        cause: 'unsupported PCP packet type or cipher',
      );
    }
    return PcpHeader._(
      encryptionMode: data[0] & 0x0F,
      exchangeKeyLabel: data[1],
      nonce: Uint8List.fromList(data.sublist(2, 10)),
      contentLength:
          (data[10] << 24) | (data[11] << 16) | (data[12] << 8) | data[13],
    );
  }
}

/// Maximum PCP content length, from the DTCP-IP specification via
/// the reference implementation: a larger header value means the
/// stream is misaligned or corrupt, and buffering for it would
/// never terminate (plan 29).
const int maxPcpContentLength = 128 * 1024 * 1024;

/// Decrypts PCP packets from a byte stream, emitting plaintext
/// incrementally as ciphertext blocks arrive (plan 30).
///
/// Incoming bytes are kept as a queue of [Uint8List] chunks with a
/// head offset, so feeding and consuming stay O(chunk). The first
/// implementation used one flat `List<int>` with `removeRange`,
/// which — combined with the real source's 1 MiB packets — made
/// the per-chunk work quadratic and pegged the UI isolate
/// (plan 29); the second waited for each whole packet before
/// decrypting, which starved the player on slow paths (plan 30).
class PcpDecryptor {
  PcpDecryptor({required this.keyForLabel});

  final Future<Uint8List> Function(int label) keyForLabel;
  final List<Uint8List> _chunks = [];
  int _buffered = 0;
  int _headOffset = 0;

  /// State of the packet currently being decrypted; null between
  /// packets (the next bytes are a header).
  _PacketState? _packet;
  int _packetsDecrypted = 0;
  int _plaintextBytes = 0;

  /// Ciphertext bytes currently buffered (diagnostics).
  int get bufferedBytes => _buffered;

  /// Packets whose ciphertext has been fully consumed.
  int get packetsDecrypted => _packetsDecrypted;

  /// Plaintext bytes emitted so far.
  int get plaintextBytes => _plaintextBytes;

  void _append(List<int> data) {
    if (data.isEmpty) return;
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    _chunks.add(chunk);
    _buffered += chunk.length;
  }

  /// Copies the first [n] buffered bytes without consuming them.
  Uint8List _peek(int n) {
    final out = Uint8List(n);
    var written = 0;
    var skip = _headOffset;
    for (final chunk in _chunks) {
      if (written >= n) break;
      final take = min(n - written, chunk.length - skip);
      out.setRange(written, written + take, chunk, skip);
      written += take;
      skip = 0;
    }
    return out;
  }

  void _drop(int n) {
    _buffered -= n;
    var remaining = n;
    while (remaining > 0) {
      final first = _chunks.first;
      final available = first.length - _headOffset;
      if (remaining < available) {
        _headOffset += remaining;
        remaining = 0;
      } else {
        remaining -= available;
        _chunks.removeAt(0);
        _headOffset = 0;
      }
    }
  }

  Uint8List _take(int n) {
    final out = _peek(n);
    _drop(n);
    return out;
  }

  /// Feeds ciphertext; returns the plaintext pieces that became
  /// available from this input (possibly partial-packet pieces,
  /// possibly none yet). Concatenating every returned piece in
  /// order yields the plaintext stream.
  Future<List<Uint8List>> add(List<int> data) async {
    _append(data);
    final out = <Uint8List>[];
    while (true) {
      final packet = _packet;
      if (packet == null) {
        if (_buffered < PcpHeader.size) break;
        final header = PcpHeader.parse(_peek(PcpHeader.size));
        if (header.contentLength > maxPcpContentLength) {
          throw NasneError.parse(
            'dtcp:pcp',
            cause:
                'the PCP content length exceeds the limit '
                '(${header.contentLength} bytes)',
          );
        }
        _drop(PcpHeader.size);
        final paddedLength = (header.contentLength + 15) & ~15;
        if (paddedLength == 0) {
          _packetsDecrypted++;
          continue;
        }
        final exchangeKey = await keyForLabel(header.exchangeKeyLabel);
        final derived = deriveContentKey(
          exchangeKey,
          header.encryptionMode,
          header.nonce,
        );
        _packet = _PacketState(
          decryptor: AesCbcDecryptor(derived.key, derived.iv),
          cipherRemaining: paddedLength,
          plainRemaining: header.contentLength,
        );
        continue;
      }
      // Inside a packet: decrypt every complete 16-byte block at
      // hand. The final block is decrypted the same way; its
      // padding tail is cut by the plaintext counter, exactly as
      // the whole-packet form cut it by length.
      final blocks = min(_buffered, packet.cipherRemaining) & ~15;
      if (blocks == 0) break;
      final cipher = _take(blocks);
      final plain = packet.decryptor.decryptBlocks(cipher, 0, blocks);
      packet.cipherRemaining -= blocks;
      final emit = min(blocks, packet.plainRemaining);
      packet.plainRemaining -= emit;
      if (emit > 0) {
        final piece = emit == plain.length
            ? plain
            : Uint8List.fromList(plain.sublist(0, emit));
        out.add(piece);
        _plaintextBytes += emit;
      }
      if (packet.cipherRemaining == 0) {
        _packet = null;
        _packetsDecrypted++;
      }
    }
    return out;
  }
}

/// CBC state of one in-flight PCP packet.
class _PacketState {
  _PacketState({
    required this.decryptor,
    required this.cipherRemaining,
    required this.plainRemaining,
  });

  final AesCbcDecryptor decryptor;

  /// Ciphertext bytes of this packet not yet consumed (padding
  /// included).
  int cipherRemaining;

  /// Plaintext bytes of this packet not yet emitted (padding
  /// excluded).
  int plainRemaining;
}
