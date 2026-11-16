/// PCP (Protected Content Packet) decryption.
///
/// Port of pydtcpip's `dtcp/pcp.py` (MIT, (c) tsukumijima). A PCP
/// packet is a 14-byte header followed by AES-128-CBC ciphertext
/// padded to a 16-byte multiple; the header's content length is the
/// authoritative plaintext length.
library;

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

/// Decrypts PCP packets from a byte stream. Ciphertext is buffered
/// until a whole packet (header + padded body) is available.
class PcpDecryptor {
  PcpDecryptor({required this.keyForLabel});

  final Future<Uint8List> Function(int label) keyForLabel;
  final List<int> _buffer = [];

  /// Feeds ciphertext; returns the plaintext of every packet that
  /// completed. Mirrors the reference's buffering behaviour.
  Future<List<Uint8List>> add(List<int> data) async {
    _buffer.addAll(data);
    final out = <Uint8List>[];
    while (true) {
      if (_buffer.length < PcpHeader.size) break;
      final header = PcpHeader.parse(_buffer);
      final paddedLength = (header.contentLength + 15) & ~15;
      final packetLength = PcpHeader.size + paddedLength;
      if (_buffer.length < packetLength) break;
      final ciphertext = _buffer.sublist(PcpHeader.size, packetLength);
      _buffer.removeRange(0, packetLength);
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
