/// Plan 29 streaming-path tests: the real nasne sends 1 MiB PCP
/// packets, and build 7 froze solid decrypting the first one (the
/// AES-CBC conversion was inside the per-block loop and the PCP
/// buffer was a flat boxed-int list). These tests pin the packet
/// scale end to end — crypto, decryptor framing, the loopback
/// proxy over real HTTP, and the re-authenticating key source.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

import 'dtcp_kat.dart';

Uint8List hex(String s) => hexToBytes(s);

/// Builds one PCP wire packet the way the source does: 14-byte
/// header + AES-128-CBC ciphertext padded to a 16-byte multiple.
Uint8List buildPcpPacket({
  required Uint8List exchangeKey,
  required int label,
  required int encryptionMode,
  required Uint8List nonce,
  required Uint8List plaintext,
}) {
  final derived = deriveContentKey(exchangeKey, encryptionMode, nonce);
  final paddedLength = (plaintext.length + 15) & ~15;
  final padded = Uint8List(paddedLength)
    ..setRange(0, plaintext.length, plaintext);
  final cipher = aesCbcEncrypt(derived.key, derived.iv, padded);
  final header = Uint8List(PcpHeader.size);
  header[0] = encryptionMode & 0x0F;
  header[1] = label;
  header.setRange(2, 10, nonce);
  final length = plaintext.length;
  header[10] = (length >> 24) & 0xFF;
  header[11] = (length >> 16) & 0xFF;
  header[12] = (length >> 8) & 0xFF;
  header[13] = length & 0xFF;
  return Uint8List.fromList([...header, ...cipher]);
}

Uint8List pattern(int length, int seed) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xFF));

void main() {
  final exchangeKey = hex(katPcpExchangeKey);
  const label = 0x2A;
  const encryptionMode = 0x04;
  final nonceA = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
  final nonceB = Uint8List.fromList([8, 7, 6, 5, 4, 3, 2, 1]);

  group('AES-CBC at PCP packet scale (plan 29)', () {
    test(
      'a 1 MiB block round-trips through encrypt and decrypt',
      () {
        final plain = pattern(1024 * 1024, 7);
        final key = pattern(16, 3);
        final iv = pattern(16, 11);
        final cipher = aesCbcEncrypt(key, iv, plain);
        final back = aesCbcDecrypt(key, iv, cipher);
        expect(back, plain);
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });

  group('PCP decryptor with 1 MiB packets (plan 29)', () {
    test(
      'two 1 MiB packets fed in 16 KiB chunks decrypt exactly',
      () async {
        final plainA = pattern(1024 * 1024, 21);
        final plainB = pattern(1024 * 1024, 99);
        final wire = Uint8List.fromList([
          ...buildPcpPacket(
            exchangeKey: exchangeKey,
            label: label,
            encryptionMode: encryptionMode,
            nonce: nonceA,
            plaintext: plainA,
          ),
          ...buildPcpPacket(
            exchangeKey: exchangeKey,
            label: label,
            encryptionMode: encryptionMode,
            nonce: nonceB,
            plaintext: plainB,
          ),
        ]);
        final decryptor = PcpDecryptor(
          keyForLabel: (requested) async {
            expect(requested, label);
            return exchangeKey;
          },
        );
        final stopwatch = Stopwatch()..start();
        final out = <Uint8List>[];
        const chunkSize = 16 * 1024;
        for (var offset = 0; offset < wire.length; offset += chunkSize) {
          final end = offset + chunkSize > wire.length
              ? wire.length
              : offset + chunkSize;
          out.addAll(await decryptor.add(wire.sublist(offset, end)));
        }
        stopwatch.stop();
        expect(out, hasLength(2));
        expect(out[0], plainA);
        expect(out[1], plainB);
        // Regression gate: the build-7 implementation needed
        // O(n^2) copies per packet (minutes, effectively a hang).
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    test('an absurd content length is a parse error, not a stall', () async {
      final header = Uint8List(PcpHeader.size);
      header[0] = encryptionMode;
      header[1] = label;
      header.setRange(2, 10, nonceA);
      header[10] = 0xFF;
      header[11] = 0xFF;
      header[12] = 0xFF;
      header[13] = 0xFF;
      final decryptor = PcpDecryptor(
        keyForLabel: (_) async => exchangeKey,
      );
      await expectLater(
        decryptor.add(header),
        throwsA(isA<NasneError>()),
      );
    });
  });

  group('proxy over loopback HTTP (plan 29)', () {
    test(
      'the player receives the decrypted 1 MiB packets in order',
      () async {
        final plainA = pattern(1024 * 1024, 5);
        final plainB = pattern(1024 * 1024, 77);
        final wire = Uint8List.fromList([
          ...buildPcpPacket(
            exchangeKey: exchangeKey,
            label: label,
            encryptionMode: encryptionMode,
            nonce: nonceA,
            plaintext: plainA,
          ),
          ...buildPcpPacket(
            exchangeKey: exchangeKey,
            label: label,
            encryptionMode: encryptionMode,
            nonce: nonceB,
            plaintext: plainB,
          ),
        ]);
        // Fake content server: serves the wire bytes in slices.
        final upstream = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        upstream.listen((request) async {
          request.response.statusCode = HttpStatus.ok;
          const slice = 64 * 1024;
          for (var offset = 0; offset < wire.length; offset += slice) {
            final end = offset + slice > wire.length
                ? wire.length
                : offset + slice;
            request.response.add(wire.sublist(offset, end));
            await request.response.flush();
          }
          await request.response.close();
        });
        final fetcher = DtcpMediaFetcher();
        final proxy = await DtcpProxy.start(
          contentUrl: Uri.parse(
            'http://127.0.0.1:${upstream.port}/web/video/pvr?id=1',
          ),
          keyForLabel: (_) async => exchangeKey,
          fetcher: fetcher,
        );
        try {
          final client = HttpClient();
          final request = await client.getUrl(proxy.uri);
          final response = await request.close();
          expect(response.statusCode, HttpStatus.ok);
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response) {
            builder.add(chunk);
          }
          client.close();
          final received = builder.takeBytes();
          expect(received.length, plainA.length + plainB.length);
          expect(
            Uint8List.fromList(received.sublist(0, plainA.length)),
            plainA,
          );
          expect(Uint8List.fromList(received.sublist(plainA.length)), plainB);
        } finally {
          await proxy.stop();
          fetcher.close();
          await upstream.close(force: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );
  });

  group('PlaybackKeySource (plan 29)', () {
    final key115 = Uint8List.fromList(List.filled(12, 0x11));
    final key116 = Uint8List.fromList(List.filled(12, 0x22));

    test('a rotated label is fetched by re-authenticating', () async {
      final first = _FakeKeySession({115: key115}, ended: true);
      final second = _FakeKeySession({116: key116});
      var reauths = 0;
      final source = PlaybackKeySource(
        session: first,
        reauthenticate: () async {
          reauths++;
          return second;
        },
      );
      // The current key is served without any re-authentication.
      expect(await source.keyForLabel(115), key115);
      expect(reauths, 0);
      // The rotated label is not on the ended session: re-auth.
      expect(await source.keyForLabel(116), key116);
      expect(reauths, 1);
      expect(source.currentSession, same(second));
      expect(first.closed, isTrue);
    });

    test('a label mismatch after re-authentication is an error', () async {
      final first = _FakeKeySession({115: key115}, ended: true);
      final second = _FakeKeySession({117: key116});
      final source = PlaybackKeySource(
        session: first,
        reauthenticate: () async => second,
      );
      await expectLater(source.keyForLabel(116), throwsA(isA<NasneError>()));
    });
  });
}

/// A scripted [ExchangeKeySession] for key-source tests.
class _FakeKeySession implements ExchangeKeySession {
  _FakeKeySession(this.keys, {this.ended = false});

  final Map<int, Uint8List> keys;
  final bool ended;
  bool closed = false;

  @override
  Uint8List? keyOrNull(int label) => keys[label];

  @override
  Future<Uint8List> waitExchangeKey(int label, {Duration? timeout}) {
    final key = keys[label];
    if (key != null) return Future.value(key);
    if (ended) return Future.error(const AkeConnectionClosed());
    // Not ended and no key: would wait for the source; the tests
    // never take this path.
    return Completer<Uint8List>().future;
  }

  @override
  Future<int> waitFirstExchangeKey({
    Duration timeout = const Duration(seconds: 20),
  }) => Future.value(keys.keys.first);

  @override
  Future<void> close() async {
    closed = true;
  }
}
