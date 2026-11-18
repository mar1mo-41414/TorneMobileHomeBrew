/// Plan 61 seekable-proxy tests.
///
/// The measured source behaviour these tests encode (2026-11-17,
/// real nasne): byte Range requests are refused with HTTP 406;
/// a GET with `TimeSeekRange.dlna.org: npt=<t>-` answers 200 with
/// the source's own time<->byte mapping in the response header,
/// and the PCP stream restarts (fresh framing, per-GET nonce) at
/// the declared start byte, which is MPEG-TTS (192-byte) aligned.
/// Packets carry 1 MiB of plaintext except the last.
///
/// The fake source below reproduces that contract over a
/// synthetic recording, with a configurable true time<->byte map
/// (piecewise linear through control points) so the proxy's map
/// estimation and overshoot retry are exercised, not assumed.
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

/// A fake nasne content endpoint with the measured contract.
class FakeNasneSource {
  FakeNasneSource({
    required this.plaintext,
    required this.durationSeconds,
    required this.mapPoints,
    required this.exchangeKey,
    required this.label,
    required this.encryptionMode,
  });

  final Uint8List plaintext;
  final double durationSeconds;

  /// The source's true map: (seconds, byte) control points,
  /// piecewise linear, starting at (0, 0) and ending at
  /// (durationSeconds, plaintext.length).
  final List<(double, int)> mapPoints;

  final Uint8List exchangeKey;
  final int label;
  final int encryptionMode;

  HttpServer? _server;
  int getCount = 0;
  int timeSeekCount = 0;
  bool sawRangeHeader = false;
  final List<double> requestedTimes = [];

  /// Test controls (plan 80): refuse the first [refuse512First]
  /// GETs with HTTP 512 (the transient refusal of plan 78.3),
  /// and/or trickle the first time-seek response's body out
  /// slowly, so a discard races a live stream. (The write-side
  /// counters only show what the source attempted: on loopback
  /// a closed peer is not observable from here — dart:io and
  /// kernel buffers absorb the writes regardless.)
  int refuse512First = 0;
  int refusedCount = 0;
  bool slowFirstTimeSeekBody = false;
  int slowChunksWritten = 0;
  int slowChunksTotal = 0;
  bool slowWriteAborted = false;

  /// Write every response body in small flushed chunks
  /// (plan 80). A single multi-megabyte write can reach the
  /// proxy as one stream event whose plaintext the pump
  /// appends in one go, sailing straight past the window cap
  /// the pause check guards; chunked writes keep the pump's
  /// pause granularity near the chunk size, which the
  /// small-window tests rely on.
  bool chunkedBodyWrites = false;
  static const int chunkSize = 64 * 1024;

  Uri get url => Uri.parse(
    'http://127.0.0.1:${_server!.port}/web/video/pvr?id=seek-test',
  );

  double byteForTime(double t) {
    if (t <= 0) return 0;
    for (var i = 1; i < mapPoints.length; i++) {
      final (t1, b1) = mapPoints[i];
      if (t <= t1) {
        final (t0, b0) = mapPoints[i - 1];
        return b0 + (b1 - b0) * (t - t0) / (t1 - t0);
      }
    }
    return plaintext.length.toDouble();
  }

  Uint8List frameFrom(int startByte, int nonceSeed) {
    final nonce = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, nonceSeed]);
    final wire = BytesBuilder(copy: false);
    var pos = startByte;
    while (pos < plaintext.length) {
      final end = pos + 1024 * 1024 < plaintext.length
          ? pos + 1024 * 1024
          : plaintext.length;
      wire.add(
        buildPcpPacket(
          exchangeKey: exchangeKey,
          label: label,
          encryptionMode: encryptionMode,
          nonce: nonce,
          plaintext: Uint8List.sublistView(plaintext, pos, end),
        ),
      );
      pos = end;
    }
    return wire.takeBytes();
  }

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) async {
      if (request.headers.value('range') != null) {
        // The measured source refuses byte ranges outright.
        sawRangeHeader = true;
        request.response.statusCode = HttpStatus.notAcceptable;
        await request.response.close();
        return;
      }
      if (refuse512First > 0) {
        refuse512First--;
        refusedCount++;
        request.response.statusCode = 512;
        await request.response.close();
        return;
      }
      getCount++;
      final seekHeader = request.headers.value('timeseekrange.dlna.org');
      var startByte = 0;
      if (seekHeader != null) {
        timeSeekCount++;
        final match = RegExp(r'npt=([0-9.]+)-').firstMatch(seekHeader);
        final t = double.parse(match!.group(1)!);
        requestedTimes.add(t);
        // The source lands on an MPEG-TTS (192-byte) boundary.
        startByte = (byteForTime(t) ~/ 192) * 192;
        request.response.headers.set(
          'TimeSeekRange.dlna.org',
          'npt=${t.toStringAsFixed(3)}-'
          '${durationSeconds.toStringAsFixed(3)}/'
          '${durationSeconds.toStringAsFixed(3)} '
          'bytes=$startByte-${plaintext.length - 1}/'
          '${plaintext.length}',
          preserveHeaderCase: true,
        );
      }
      request.response.statusCode = HttpStatus.ok;
      final wire = frameFrom(startByte, getCount & 0xFF);
      if (seekHeader != null && slowFirstTimeSeekBody && timeSeekCount == 1) {
        slowChunksTotal = (wire.length + chunkSize - 1) ~/ chunkSize;
        try {
          await request.response.flush();
          var offset = 0;
          while (offset < wire.length) {
            final end = offset + chunkSize > wire.length
                ? wire.length
                : offset + chunkSize;
            request.response.add(Uint8List.sublistView(wire, offset, end));
            await request.response.flush();
            slowChunksWritten++;
            offset = end;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await request.response.close();
        } catch (_) {
          slowWriteAborted = true;
        }
        return;
      }
      try {
        if (chunkedBodyWrites) {
          var offset = 0;
          while (offset < wire.length) {
            final end = offset + chunkSize > wire.length
                ? wire.length
                : offset + chunkSize;
            request.response.add(Uint8List.sublistView(wire, offset, end));
            await request.response.flush();
            offset = end;
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
          await request.response.close();
        } else {
          request.response.add(wire);
          await request.response.close();
        }
      } catch (_) {
        // A client that stops reading (a superseded producer, a
        // discarded overshoot response) tears the connection
        // down mid-write; a real server sees the same.
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}

void main() {
  final exchangeKey = hex(katPcpExchangeKey);
  const label = 0x2A;
  const encryptionMode = 0x04;
  const durationSeconds = 600.0;

  // 3 full 1 MiB packets + an unaligned tail.
  final plain = pattern(3 * 1024 * 1024 + 123457, 17);
  final total = plain.length;

  FakeNasneSource linearSource() => FakeNasneSource(
    plaintext: plain,
    durationSeconds: durationSeconds,
    mapPoints: [(0.0, 0), (durationSeconds, total)],
    exchangeKey: exchangeKey,
    label: label,
    encryptionMode: encryptionMode,
  );

  Future<(DtcpProxy, DtcpMediaFetcher)> startProxy(
    FakeNasneSource source,
  ) async {
    final fetcher = DtcpMediaFetcher();
    final proxy = await DtcpProxy.start(
      contentUrl: source.url,
      keyForLabel: (_) async => exchangeKey,
      fetcher: fetcher,
      totalBytes: total,
      totalDuration: const Duration(seconds: 600),
    );
    return (proxy, fetcher);
  }

  Future<(int, HttpHeaders, Uint8List)> fetch(
    Uri uri, {
    String? range,
    bool head = false,
  }) async {
    final client = HttpClient();
    try {
      final request = head
          ? await client.headUrl(uri)
          : await client.getUrl(uri);
      if (range != null) request.headers.set('Range', range);
      final response = await request.close();
      final body = await response
          .fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (builder, chunk) => builder..add(chunk),
          )
          .then((builder) => builder.takeBytes());
      return (
        response.statusCode,
        response.headers,
        Uint8List.fromList(body),
      );
    } finally {
      client.close();
    }
  }

  group('fetcher time seek (plan 61)', () {
    test('openContentAtTime parses the mapping header', () async {
      final source = linearSource();
      await source.start();
      final fetcher = DtcpMediaFetcher();
      try {
        final tsr = await fetcher.openContentAtTime(source.url, 300.0);
        // Linear map: t=300 -> byte total/2, 192-aligned down.
        final expected = (total ~/ 2 ~/ 192) * 192;
        expect(tsr.startByte, expected);
        expect(tsr.startSeconds, 300.0);
        expect(tsr.totalBytes, total);
        expect(tsr.totalSeconds, durationSeconds);
        await tsr.response.drain<void>();
      } finally {
        fetcher.close();
        await source.stop();
      }
    });

    test('a byte Range against the source is a 406 NasneError', () async {
      final source = linearSource();
      await source.start();
      final fetcher = DtcpMediaFetcher();
      try {
        // The fetcher never sends Range; drive the fake's refusal
        // through a raw client to pin the measured contract.
        final client = HttpClient();
        final request = await client.getUrl(source.url);
        request.headers.set('Range', 'bytes=0-13');
        final response = await request.close();
        expect(response.statusCode, HttpStatus.notAcceptable);
        await response.drain<void>();
        client.close();
        expect(source.sawRangeHeader, isTrue);
      } finally {
        fetcher.close();
        await source.stop();
      }
    });
  });

  group('seekable proxy (plan 61)', () {
    test('a full GET advertises seekability and serves exactly', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        final (status, headers, body) = await fetch(proxy.uri);
        expect(status, HttpStatus.ok);
        expect(headers.value('accept-ranges'), 'bytes');
        expect(headers.contentLength, total);
        expect(body, plain);
        expect(source.sawRangeHeader, isFalse);
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('HEAD answers the seekable headers with no body', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        final (status, headers, body) = await fetch(proxy.uri, head: true);
        expect(status, HttpStatus.ok);
        expect(headers.value('accept-ranges'), 'bytes');
        expect(headers.contentLength, total);
        expect(body, isEmpty);
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a bounded range mid-file is byte-exact', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        const start = 1500001; // unaligned, mid-packet
        const end = 1800000;
        final (status, headers, body) = await fetch(
          proxy.uri,
          range: 'bytes=$start-$end',
        );
        expect(status, HttpStatus.partialContent);
        expect(
          headers.value('content-range'),
          'bytes $start-$end/$total',
        );
        expect(headers.contentLength, end - start + 1);
        expect(body, Uint8List.sublistView(plain, start, end + 1));
        expect(source.sawRangeHeader, isFalse);
        expect(source.timeSeekCount, greaterThanOrEqualTo(1));
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an open-ended range serves the exact suffix', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        const start = 2500003;
        final (status, headers, body) = await fetch(
          proxy.uri,
          range: 'bytes=$start-',
        );
        expect(status, HttpStatus.partialContent);
        expect(
          headers.value('content-range'),
          'bytes $start-${total - 1}/$total',
        );
        expect(body, Uint8List.sublistView(plain, start));
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a suffix range serves the exact tail', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        const suffix = 100000;
        final (status, headers, body) = await fetch(
          proxy.uri,
          range: 'bytes=-$suffix',
        );
        expect(status, HttpStatus.partialContent);
        expect(
          headers.value('content-range'),
          'bytes ${total - suffix}-${total - 1}/$total',
        );
        expect(body, Uint8List.sublistView(plain, total - suffix));
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a range beyond the content is 416', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        final (status, headers, body) = await fetch(
          proxy.uri,
          range: 'bytes=$total-',
        );
        expect(status, HttpStatus.requestedRangeNotSatisfiable);
        expect(headers.value('content-range'), 'bytes */$total');
        expect(body, isEmpty);
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an overshooting estimate is corrected by a retry', () async {
      // True map: a dense first segment (6000 B/s to t=300) and a
      // sparse rest (4910 B/s). The proxy's linear estimate for a
      // target in the sparse region asks too late and the source's
      // start byte overshoots the target on the first attempt.
      final kinked = FakeNasneSource(
        plaintext: plain,
        durationSeconds: durationSeconds,
        mapPoints: [
          (0.0, 0),
          (300.0, 1800000),
          (durationSeconds, total),
        ],
        exchangeKey: exchangeKey,
        label: label,
        encryptionMode: encryptionMode,
      );
      await kinked.start();
      final (proxy, fetcher) = await startProxy(kinked);
      try {
        const start = 2600000;
        const end = 2700000;
        final (status, headers, body) = await fetch(
          proxy.uri,
          range: 'bytes=$start-$end',
        );
        expect(status, HttpStatus.partialContent);
        expect(
          headers.value('content-range'),
          'bytes $start-$end/$total',
        );
        expect(body, Uint8List.sublistView(plain, start, end + 1));
        // The first attempt overshot; a corrected second attempt
        // must have happened.
        expect(kinked.timeSeekCount, greaterThanOrEqualTo(2));
      } finally {
        await proxy.stop();
        fetcher.close();
        await kinked.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('sequential seeks to different regions are both exact', () async {
      final source = linearSource();
      await source.start();
      final (proxy, fetcher) = await startProxy(source);
      try {
        final first = await fetch(proxy.uri, range: 'bytes=2000000-2100000');
        expect(first.$1, HttpStatus.partialContent);
        expect(
          first.$3,
          Uint8List.sublistView(plain, 2000000, 2100001),
        );
        final second = await fetch(proxy.uri, range: 'bytes=100000-200000');
        expect(second.$1, HttpStatus.partialContent);
        expect(
          second.$3,
          Uint8List.sublistView(plain, 100000, 200001),
        );
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a backward seek inside the window needs no new GET', () async {
      final small = pattern(2 * 1024 * 1024 + 999, 41);
      final source = FakeNasneSource(
        plaintext: small,
        durationSeconds: durationSeconds,
        mapPoints: [(0.0, 0), (durationSeconds, small.length)],
        exchangeKey: exchangeKey,
        label: label,
        encryptionMode: encryptionMode,
      );
      await source.start();
      final fetcher = DtcpMediaFetcher();
      final proxy = await DtcpProxy.start(
        contentUrl: source.url,
        keyForLabel: (_) async => exchangeKey,
        fetcher: fetcher,
        totalBytes: small.length,
        totalDuration: const Duration(seconds: 600),
      );
      try {
        // Play the whole stream once: the window now holds it all.
        final full = await fetch(proxy.uri);
        expect(full.$1, HttpStatus.ok);
        expect(full.$3, small);
        final getsAfterPlay = source.getCount;
        final back = await fetch(proxy.uri, range: 'bytes=500000-600000');
        expect(back.$1, HttpStatus.partialContent);
        expect(back.$3, Uint8List.sublistView(small, 500000, 600001));
        expect(source.getCount, getsAfterPlay);
      } finally {
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'a far seek is not stalled by a previous reader\'s leftover '
      'pin (plan 80 regression)',
      () async {
        // Fixture sized against the overridden window cap: the
        // content is ~33.7 MB with a 16 MiB cap, so a reader
        // pinned near the head leaves the tail anchor more than
        // a cap behind it — the geometry of the plan-78 stall.
        // (The reader below can only block in flush() because
        // the cap exceeds what the loopback socket buffers can
        // absorb; on this machine that is ~10 MiB at most.)
        final big = pattern(32 * 1024 * 1024 + 123457, 23);
        final bigTotal = big.length;
        final source = FakeNasneSource(
          plaintext: big,
          durationSeconds: durationSeconds,
          mapPoints: [(0.0, 0), (durationSeconds, bigTotal)],
          exchangeKey: exchangeKey,
          label: label,
          encryptionMode: encryptionMode,
        );
        await source.start();
        final fetcher = DtcpMediaFetcher();
        final proxy = await DtcpProxy.start(
          contentUrl: source.url,
          keyForLabel: (_) async => exchangeKey,
          fetcher: fetcher,
          totalBytes: bigTotal,
          totalDuration: const Duration(seconds: 600),
          windowCapBytesOverride: 16 * 1024 * 1024,
        );
        Socket? socketA;
        try {
          // Reader A takes the stream from the head and stops
          // reading after a small prefix: its serve handler
          // blocks in flush() with its pin left partway into
          // the content — the state the player leaves behind
          // when it abandons a connection at a seek (plan 78.2).
          socketA = await Socket.connect(
            InternetAddress.loopbackIPv4,
            proxy.uri.port,
          );
          socketA.write(
            'GET /stream HTTP/1.1\r\n'
            'Host: 127.0.0.1\r\n'
            'Range: bytes=0-\r\n'
            'Connection: close\r\n\r\n',
          );
          var receivedA = 0;
          final prefix = Completer<void>();
          final subA = socketA.listen((chunk) {
            receivedA += chunk.length;
            if (receivedA >= 128 * 1024 && !prefix.isCompleted) {
              prefix.complete();
            }
          });
          await prefix.future.timeout(const Duration(seconds: 20));
          subA.pause();
          // Let A's handler run into the blocked flush and the
          // producer settle against A's pin.
          await Future<void>.delayed(const Duration(seconds: 3));

          // Reader B seeks far beyond the window A left behind.
          // With the leftover pin honoured, the new producer
          // starts out already "a full window ahead" of the pin
          // and never reads a byte (plan 78.2); B's fetch then
          // hangs and this timeout fails the test.
          const start = 33000000;
          const end = 33100000;
          final result = await fetch(
            proxy.uri,
            range: 'bytes=$start-$end',
          ).timeout(const Duration(seconds: 20));
          expect(result.$1, HttpStatus.partialContent);
          expect(
            result.$2.value('content-range'),
            'bytes $start-$end/$bigTotal',
          );
          expect(result.$3, Uint8List.sublistView(big, start, end + 1));
          await subA.cancel();
        } finally {
          socketA?.destroy();
          await proxy.stop();
          fetcher.close();
          await source.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 120)),
    );

    /// Starts a proxy over [source] with a small window cap so
    /// a far target stays outside the window deterministically,
    /// and waits until the primer's initial GET has reached
    /// the source (after which arming refusals cannot hit it).
    Future<(DtcpProxy, DtcpMediaFetcher)> startProxySmallWindow(
      FakeNasneSource source,
    ) async {
      source.chunkedBodyWrites = true;
      final fetcher = DtcpMediaFetcher();
      final proxy = await DtcpProxy.start(
        contentUrl: source.url,
        keyForLabel: (_) async => exchangeKey,
        fetcher: fetcher,
        totalBytes: total,
        totalDuration: const Duration(seconds: 600),
        windowCapBytesOverride: 256 * 1024,
      );
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (source.getCount < 1 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(source.getCount, greaterThanOrEqualTo(1));
      return (proxy, fetcher);
    }

    test(
      'a time seek refused with 512 is retried with backoff '
      '(plan 80)',
      () async {
        final source = linearSource();
        await source.start();
        final (proxy, fetcher) = await startProxySmallWindow(source);
        try {
          source.refuse512First = 2;
          const start = 2600000;
          const end = 2700000;
          final stopwatch = Stopwatch()..start();
          final (status, headers, body) = await fetch(
            proxy.uri,
            range: 'bytes=$start-$end',
          );
          expect(status, HttpStatus.partialContent);
          expect(
            headers.value('content-range'),
            'bytes $start-$end/$total',
          );
          expect(body, Uint8List.sublistView(plain, start, end + 1));
          expect(source.refusedCount, 2);
          expect(source.timeSeekCount, greaterThanOrEqualTo(1));
          // The 500 ms + 1 s backoffs must have elapsed; an
          // immediate-retry implementation would finish well
          // under this bound.
          expect(
            stopwatch.elapsedMilliseconds,
            greaterThanOrEqualTo(1000),
          );
        } finally {
          await proxy.stop();
          fetcher.close();
          await source.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'a persistent 512 falls back to a plain GET that is also '
      'retried (plan 80)',
      () async {
        final source = linearSource();
        await source.start();
        final (proxy, fetcher) = await startProxySmallWindow(source);
        try {
          // Four refusals exhaust the time seek's retries
          // (initial + 3); two more meet the plain GET's first
          // attempts before it succeeds.
          source.refuse512First = 6;
          const start = 2600000;
          const end = 2700000;
          final (status, headers, body) = await fetch(
            proxy.uri,
            range: 'bytes=$start-$end',
          );
          expect(status, HttpStatus.partialContent);
          expect(
            headers.value('content-range'),
            'bytes $start-$end/$total',
          );
          expect(body, Uint8List.sublistView(plain, start, end + 1));
          expect(source.refusedCount, 6);
        } finally {
          await proxy.stop();
          fetcher.close();
          await source.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'a slow overshoot response is discarded and the seek '
      'retried (plan 80)',
      () async {
        // The kinked map of the overshoot test: the first
        // attempt lands past the target. Its body trickles out
        // slowly, so the discard (plan 80: cancel the
        // subscription, closing the connection, instead of
        // draining the body to its end) races a live stream —
        // the condition the real overshoot of plan 78.3
        // presented. Whether the source's writes stop is not
        // assertable on loopback: dart:io and kernel buffers
        // absorb even tens of megabytes from a closed peer
        // (probed 2026-11-18), so this test pins the retry's
        // correctness under that race, and the discard change
        // itself stands on the proxy no longer reading the
        // body at all.
        final kinked = FakeNasneSource(
          plaintext: plain,
          durationSeconds: durationSeconds,
          mapPoints: [
            (0.0, 0),
            (300.0, 1800000),
            (durationSeconds, total),
          ],
          exchangeKey: exchangeKey,
          label: label,
          encryptionMode: encryptionMode,
        );
        kinked.slowFirstTimeSeekBody = true;
        await kinked.start();
        final (proxy, fetcher) = await startProxySmallWindow(kinked);
        try {
          const start = 2600000;
          const end = 2700000;
          final (status, headers, body) = await fetch(
            proxy.uri,
            range: 'bytes=$start-$end',
          );
          expect(status, HttpStatus.partialContent);
          expect(
            headers.value('content-range'),
            'bytes $start-$end/$total',
          );
          expect(body, Uint8List.sublistView(plain, start, end + 1));
          expect(kinked.timeSeekCount, greaterThanOrEqualTo(2));
          expect(kinked.slowChunksTotal, greaterThanOrEqualTo(5));
        } finally {
          await proxy.stop();
          fetcher.close();
          await kinked.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
