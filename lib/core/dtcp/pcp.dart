/// PCP (Protected Content Packet) decryption.
///
/// Port of pydtcpip's `dtcp/pcp.py` (MIT, (c) tsukumijima). A PCP
/// packet is a 14-byte header followed by AES-128-CBC ciphertext
/// padded to a 16-byte multiple; the header's content length is the
/// authoritative plaintext length.
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

/// Decrypts PCP packets from a byte stream. Ciphertext is buffered
/// until a whole packet (header + padded body) is available.
///
/// Incoming bytes are kept as a queue of [Uint8List] chunks with a
/// head offset, so feeding and consuming stay O(chunk). The first
/// implementation used one flat `List<int>` with `removeRange`,
/// which — combined with the real source's 1 MiB packets — made
/// the per-chunk work quadratic and pegged the UI isolate
/// (plan 29).
class PcpDecryptor {
  PcpDecryptor({required this.keyForLabel});

  final Future<Uint8List> Function(int label) keyForLabel;
  final List<Uint8List> _chunks = [];
  int _buffered = 0;
  int _headOffset = 0;

  /// Ciphertext bytes currently buffered (diagnostics).
  int get bufferedBytes => _buffered;

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

  /// Feeds ciphertext; returns the plaintext of every packet that
  /// completed. Mirrors the reference's packet-at-a-time framing.
  Future<List<Uint8List>> add(List<int> data) async {
    _append(data);
    final out = <Uint8List>[];
    while (true) {
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
      final paddedLength = (header.contentLength + 15) & ~15;
      final packetLength = PcpHeader.size + paddedLength;
      if (_buffered < packetLength) break;
      _drop(PcpHeader.size);
      final ciphertext = _take(paddedLength);
      final exchangeKey = await keyForLabel(header.exchangeKeyLabel);
      final derived = deriveContentKey(
        exchangeKey,
        header.encryptionMode,
        header.nonce,
      );
      final plain = aesCbcDecrypt(derived.key, derived.iv, ciphertext);
      out.add(Uint8List.fromList(plain.sublist(0, header.contentLength)));
    }
    return out;
  }
}
