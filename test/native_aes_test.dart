/// Native AES verification: the C implementation in
/// android/app/src/main/cpp/tmhb_aes.c (driven through
/// lib/core/dtcp/native_aes.dart) must produce byte-identical
/// output to the Dart (pointycastle) implementation it replaces
/// on Android.
///
/// The tests load a host build of the same C file
/// (build/native_test/libtmhb_aes.so, produced by
/// tool/build_native_aes_host.sh; the path can be overridden with
/// the TMHB_NATIVE_AES_LIB environment variable). When the host
/// library is absent the native groups are skipped, so a plain
/// `flutter test` on a machine without a C compiler stays green;
/// the byte-identity gate is enforced wherever the library has
/// been built.
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

String? hostLibraryPath() {
  final env = Platform.environment['TMHB_NATIVE_AES_LIB'];
  if (env != null && File(env).existsSync()) return env;
  const candidate = 'build/native_test/libtmhb_aes.so';
  if (File(candidate).existsSync()) return candidate;
  return null;
}

Uint8List randomBytes(Random rng, int length) =>
    Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));

/// Feeds [cipher] through [decryptor] in block-aligned pieces whose
/// sizes cycle through [pieceSizes], passing the whole buffer with
/// an advancing offset (the decryptBlocks contract), and returns
/// the concatenated plaintext.
Uint8List decryptInPieces(
  AesCbcDecryptor decryptor,
  Uint8List cipher,
  List<int> pieceSizes,
) {
  final builder = BytesBuilder(copy: false);
  var offset = 0;
  var i = 0;
  while (offset < cipher.length) {
    var take = pieceSizes[i++ % pieceSizes.length];
    if (take > cipher.length - offset) take = cipher.length - offset;
    builder.add(decryptor.decryptBlocks(cipher, offset, take));
    offset += take;
  }
  return builder.toBytes();
}

/// A PcpDecryptor-style consumer for arbitrarily split input: bytes
/// are buffered until a whole 16-byte block is available, so splits
/// in the middle of a block are absorbed here, exactly as the PCP
/// framing absorbs them in production.
class BlockAligningDecryptor {
  BlockAligningDecryptor(this._inner);

  final AesCbcDecryptor _inner;
  final BytesBuilder _out = BytesBuilder(copy: false);
  Uint8List _tail = Uint8List(0);

  void add(Uint8List chunk) {
    final joined = Uint8List.fromList([..._tail, ...chunk]);
    final blocks = joined.length & ~15;
    if (blocks > 0) {
      _out.add(_inner.decryptBlocks(joined, 0, blocks));
    }
    _tail = Uint8List.fromList(joined.sublist(blocks));
  }

  Uint8List finish() {
    expect(_tail, isEmpty, reason: 'input must be a multiple of 16 overall');
    return _out.toBytes();
  }
}

void main() {
  // NIST SP 800-38A F.2.1 / F.2.2 (CBC-AES128).
  final nistKey = hexToBytes('2b7e151628aed2a6abf7158809cf4f3c');
  final nistIv = hexToBytes('000102030405060708090a0b0c0d0e0f');
  final nistPlain = hexToBytes(
    '6bc1bee22e409f96e93d7e117393172a'
    'ae2d8a571e03ac9c9eb76fac45af8e51'
    '30c81c46a35ce411e5fbc1191a0a52ef'
    'f69f2445df4f9b17ad2b417be66c3710',
  );
  final nistCipher = hexToBytes(
    '7649abac8119b246cee98e9b12e9197d'
    '5086cb9b507219ee95db113a917678b2'
    '73bed6b8e3c1743b7116e69e22229516'
    '3ff1caa1681fac09120eca307586e1a7',
  );

  test('the Dart reference itself matches the NIST vector', () {
    expect(aesCbcDecrypt(nistKey, nistIv, nistCipher), nistPlain);
  });

  test('the process-wide instance is null on a non-Android host', () {
    expect(NativeAesBackend.instance, isNull);
    expect(NativeAesBackend.tryLoad(libraryPath: '/nonexistent.so'), isNull);
  });

  final libPath = hostLibraryPath();
  group(
    'native AES backend (host build of tmhb_aes.c)',
    () {
      late NativeAesBackend backend;

      setUpAll(() {
        backend = NativeAesBackend.tryLoad(libraryPath: libPath)!;
      });

      tearDownAll(() {
        backend.dispose();
      });

      test('NIST SP 800-38A CBC-AES128 vector, backend directly', () {
        final rk = backend.expandDecKey(nistKey);
        final iv = Uint8List.fromList(nistIv);
        final out = backend.decryptCbc(
          rk,
          iv,
          nistCipher,
          0,
          nistCipher.length,
        );
        expect(out, nistPlain);
        // The chain contract: iv ends as the last ciphertext block.
        expect(iv, nistCipher.sublist(nistCipher.length - 16));
      });

      test('NIST vector through AesCbcDecryptor, split 16 + 48', () {
        final decryptor = AesCbcDecryptor(
          nistKey,
          nistIv,
          nativeBackend: backend,
        );
        final out = decryptInPieces(decryptor, nistCipher, [16, 48]);
        expect(out, nistPlain);
      });

      test('randomized byte identity vs the Dart implementation', () {
        final rng = Random(0xCBC128);
        const lengths = [16, 48, 256, 4096, 65536, 65552, 131088, 1048576];
        for (final length in lengths) {
          final key = randomBytes(rng, 16);
          final iv = randomBytes(rng, 16);
          final plain = randomBytes(rng, length);
          final cipher = aesCbcEncrypt(key, iv, plain);

          // One-shot Dart reference.
          expect(aesCbcDecrypt(key, iv, cipher), plain, reason: 'len=$length');

          // Native backend, one shot.
          final rk = backend.expandDecKey(key);
          final chain = Uint8List.fromList(iv);
          expect(
            backend.decryptCbc(rk, chain, cipher, 0, length),
            plain,
            reason: 'len=$length',
          );
          expect(chain, cipher.sublist(length - 16), reason: 'len=$length');

          // Native streaming decryptor in block-aligned pieces,
          // including pieces that straddle the backend's 64 KiB
          // staging chunk.
          final streaming = AesCbcDecryptor(key, iv, nativeBackend: backend);
          final out = decryptInPieces(streaming, cipher, [
            16,
            1024,
            65536,
            65552,
            48,
          ]);
          expect(out, plain, reason: 'len=$length');
        }
      }, timeout: const Timeout(Duration(seconds: 120)));

      test('mid-block splits of the ciphertext stream decrypt exactly', () {
        final rng = Random(0x5EED);
        final key = randomBytes(rng, 16);
        final iv = randomBytes(rng, 16);
        final plain = randomBytes(rng, 16 * 1024);
        final cipher = aesCbcEncrypt(key, iv, plain);

        // Split sizes deliberately land inside blocks (1, 15, 17,
        // 31, ...) as network chunks do; the aligning consumer
        // buffers to block boundaries before decrypting.
        const splits = [1, 15, 16, 17, 31, 100, 7, 4099, 3, 1024, 255];
        for (final useNative in [true, false]) {
          final aligning = BlockAligningDecryptor(
            AesCbcDecryptor(key, iv, nativeBackend: useNative ? backend : null),
          );
          var offset = 0;
          var i = 0;
          while (offset < cipher.length) {
            var take = splits[i++ % splits.length];
            if (take > cipher.length - offset) {
              take = cipher.length - offset;
            }
            aligning.add(cipher.sublist(offset, offset + take));
            offset += take;
          }
          expect(aligning.finish(), plain, reason: 'native=$useNative');
        }
      });

      test('throughput comparison (informational)', () {
        final rng = Random(0xBE11);
        final key = randomBytes(rng, 16);
        final iv = randomBytes(rng, 16);
        const length = 16 * 1024 * 1024;
        final plain = randomBytes(rng, length);
        final cipher = aesCbcEncrypt(key, iv, plain);

        final dartWatch = Stopwatch()..start();
        final dartOut = aesCbcDecrypt(key, iv, cipher);
        dartWatch.stop();
        expect(dartOut, plain);

        final rk = backend.expandDecKey(key);
        final nativeWatch = Stopwatch()..start();
        final nativeOut = backend.decryptCbc(
          rk,
          Uint8List.fromList(iv),
          cipher,
          0,
          length,
        );
        nativeWatch.stop();
        expect(nativeOut, plain);

        String mibPerSec(Stopwatch w) =>
            (length / w.elapsedMicroseconds * 1e6 / (1024 * 1024))
                .toStringAsFixed(1);
        // ignore: avoid_print
        print(
          'AES-128-CBC decrypt of 16 MiB: '
          'Dart ${mibPerSec(dartWatch)} MiB/s, '
          'native ${mibPerSec(nativeWatch)} MiB/s',
        );
      }, timeout: const Timeout(Duration(seconds: 180)));
    },
    skip: libPath == null
        ? 'host native library not built; run tool/build_native_aes_host.sh'
        : false,
  );
}
