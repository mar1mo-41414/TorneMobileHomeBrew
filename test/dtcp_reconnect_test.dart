/// Plan 129 proxy auto-reconnect tests: when the engine enables
/// it (Android), a dropped upstream connection is recovered
/// inside the proxy instead of ending playback — live streams
/// reconnect with backoff and a fresh authentication, recordings
/// resume the producer at the reader's byte. Committed refusals
/// (404 and friends) still surface as failures, and a recording
/// that is not live never reconnects: an unseekable stream
/// cannot resume mid-way, and re-serving it from byte 0 into
/// the same response would corrupt the player's stream.
///
/// The harnesses follow the sibling suites: real loopback HTTP
/// on both sides, PCP packets built with the KAT exchange key,
/// socket destruction to simulate mid-body drops.
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

/// Reads a client stream to its end (or its error), returning
/// what arrived and the error, if any.
Future<(Uint8List, Object?)> collectAll(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  Object? error;
  try {
    await for (final chunk in stream) {
      builder.add(chunk);
    }
  } catch (e) {
    error = e;
  }
  return (builder.takeBytes(), error);
}

/// Reads until [count] bytes have arrived, then stops.
Future<Uint8List> readExactly(Stream<List<int>> stream, int count) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream.timeout(const Duration(seconds: 20))) {
    builder.add(chunk);
    if (builder.length >= count) break;
  }
  return builder.takeBytes();
}

/// A scripted legacy (unseekable) upstream: the handler decides
/// per attempt what the source does.
class ScriptedLiveSource {
  ScriptedLiveSource(this.handler);

  final Future<void> Function(HttpRequest request, int attempt) handler;

  HttpServer? _server;
  int attempts = 0;

  Uri get url => Uri.parse('http://127.0.0.1:${_server!.port}/live');

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) {
      attempts++;
      unawaited(handler(request, attempts));
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}

Future<void> serveWire(HttpRequest request, Uint8List wire) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.add(wire);
  await request.response.close();
}

/// Serves a prefix of [wire], then destroys the socket: the
/// mid-body drop of an unstable link. The detach must happen
/// before any flush (a sent head can no longer be detached),
/// so the full length is declared up front and the head goes
/// out with the detach.
Future<void> dropMidBody(
  HttpRequest request,
  Uint8List wire,
  int keepBytes,
) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.contentLength = wire.length;
  final socket = await request.response.detachSocket();
  socket.add(Uint8List.sublistView(wire, 0, keepBytes));
  await socket.flush();
  socket.destroy();
}

/// A seekable fake source with the measured contract (byte
/// Range refused with 406, time seek answered with the source's
/// own start byte), plus drop controls: the plain GET can be
/// cut mid-body, and time seeks can be refused with 503 (a
/// transient outage) or 404 (a committed refusal). The byte<->time
/// map is linear at [bytesPerSecond]; the declared total can
/// exceed the bytes the source actually holds (the clean-EOF
/// case).
class DropSeekSource {
  DropSeekSource({
    required this.actualPlaintext,
    required this.declaredTotal,
    required this.exchangeKey,
    required this.label,
    required this.encryptionMode,
  });

  final Uint8List actualPlaintext;
  final int declaredTotal;
  final Uint8List exchangeKey;
  final int label;
  final int encryptionMode;

  static const double bytesPerSecond = 24000.0;
  double get durationSeconds => declaredTotal / bytesPerSecond;

  HttpServer? _server;
  int getCount = 0;
  int timeSeekCount = 0;
  final List<int> declaredStarts = [];

  /// Wire bytes of the plain GET to emit before destroying the
  /// socket; -1 serves the whole body.
  int plainGetDropAfterWireBytes = -1;

  /// Refuse this many time-seek GETs with 503 before serving.
  int timeSeek503Remaining = 0;

  /// Refuse every time-seek GET with 404.
  bool timeSeek404 = false;

  Uri get url =>
      Uri.parse('http://127.0.0.1:${_server!.port}/web/video/pvr?id=rc-test');

  Uint8List frameFrom(int startByte, int nonceSeed) {
    final nonce = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, nonceSeed]);
    final wire = BytesBuilder(copy: false);
    var pos = startByte;
    while (pos < actualPlaintext.length) {
      final end = pos + 1024 * 1024 < actualPlaintext.length
          ? pos + 1024 * 1024
          : actualPlaintext.length;
      wire.add(
        buildPcpPacket(
          exchangeKey: exchangeKey,
          label: label,
          encryptionMode: encryptionMode,
          nonce: nonce,
          plaintext: Uint8List.sublistView(actualPlaintext, pos, end),
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
        request.response.statusCode = HttpStatus.notAcceptable;
        await request.response.close();
        return;
      }
      final seekHeader = request.headers.value('timeseekrange.dlna.org');
      if (seekHeader != null) {
        timeSeekCount++;
        if (timeSeek404) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        if (timeSeek503Remaining > 0) {
          timeSeek503Remaining--;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final match = RegExp(r'npt=([0-9.]+)-').firstMatch(seekHeader);
        final t = double.parse(match!.group(1)!);
        var startByte = (t * bytesPerSecond).floor();
        startByte = (startByte ~/ 192) * 192;
        declaredStarts.add(startByte);
        request.response.headers.set(
          'TimeSeekRange.dlna.org',
          'npt=${t.toStringAsFixed(3)}-'
              '${durationSeconds.toStringAsFixed(3)}/'
              '${durationSeconds.toStringAsFixed(3)} '
              'bytes=$startByte-${declaredTotal - 1}/$declaredTotal',
          preserveHeaderCase: true,
        );
        request.response.statusCode = HttpStatus.ok;
        try {
          request.response.add(frameFrom(startByte, timeSeekCount & 0xFF));
          await request.response.close();
        } catch (_) {
          // The proxy walked away mid-write (a superseded or
          // discarded producer); a real server sees the same.
        }
        return;
      }
      getCount++;
      declaredStarts.add(0);
      request.response.statusCode = HttpStatus.ok;
      final wire = frameFrom(0, getCount & 0xFF);
      final drop = plainGetDropAfterWireBytes;
      if (drop >= 0 && drop < wire.length) {
        try {
          request.response.contentLength = wire.length;
          final socket = await request.response.detachSocket();
          socket.add(Uint8List.sublistView(wire, 0, drop));
          await socket.flush();
          socket.destroy();
        } catch (_) {}
        return;
      }
      try {
        request.response.add(wire);
        await request.response.close();
      } catch (_) {}
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}

class _FakeKeySession implements ExchangeKeySession {
  _FakeKeySession(this.keys);

  final Map<int, Uint8List> keys;
  bool closed = false;

  @override
  Uint8List? keyOrNull(int label) => keys[label];

  @override
  Future<Uint8List> waitExchangeKey(int label, {Duration? timeout}) {
    final key = keys[label];
    if (key != null) return Future.value(key);
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

void main() {
  final exchangeKey = hex(katPcpExchangeKey);
  const label = 0x2A;
  const encryptionMode = 0x04;
  final nonce = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

  const testBackoff = [
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
  ];

  group('legacy live reconnect (plan 129)', () {
    test(
      'a clean end and a 503 are recovered: the player receives '
      'both packets over one connection, with one re-authentication',
      () async {
        final plainA = pattern(64 * 1024, 21);
        final plainB = pattern(64 * 1024, 99);
        final wireA = buildPcpPacket(
          exchangeKey: exchangeKey,
          label: label,
          encryptionMode: encryptionMode,
          nonce: nonce,
          plaintext: plainA,
        );
        final wireB = buildPcpPacket(
          exchangeKey: exchangeKey,
          label: label,
          encryptionMode: encryptionMode,
          nonce: nonce,
          plaintext: plainB,
        );
        final servedKinds = <String>[];
        final source = ScriptedLiveSource((request, attempt) async {
          if (attempt == 2) {
            servedKinds.add('503');
            request.response.statusCode = HttpStatus.serviceUnavailable;
            await request.response.close();
            return;
          }
          servedKinds.add('packet');
          await serveWire(request, attempt == 1 ? wireA : wireB);
        });
        await source.start();
        var reauthCount = 0;
        final fetcher = DtcpMediaFetcher();
        final proxy = await DtcpProxy.start(
          contentUrl: source.url,
          keyForLabel: (_) async => exchangeKey,
          fetcher: fetcher,
          isLive: true,
          autoReconnect: true,
          onReauthenticate: () async {
            reauthCount++;
          },
          reconnectBackoff: testBackoff,
        );
        final client = HttpClient();
        try {
          final request = await client.getUrl(proxy.uri);
          final response = await request.close();
          final received = await readExactly(
            response,
            plainA.length + plainB.length,
          );
          expect(received.length, plainA.length + plainB.length);
          expect(
            received,
            Uint8List.fromList([...plainA, ...plainB]),
            reason:
                'the reconnected stream must continue '
                'byte-exactly where the dropped one ended',
          );
          expect(servedKinds.take(3), ['packet', '503', 'packet']);
          expect(
            reauthCount,
            1,
            reason:
                'the 503 attempt is preceded by exactly one '
                'forced re-authentication',
          );
        } finally {
          client.close(force: true);
          await proxy.stop();
          fetcher.close();
          await source.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'a committed refusal (404) surfaces instead of reconnecting',
      () async {
        final source = ScriptedLiveSource((request, attempt) async {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });
        await source.start();
        var reauthCount = 0;
        final fetcher = DtcpMediaFetcher();
        final proxy = await DtcpProxy.start(
          contentUrl: source.url,
          keyForLabel: (_) async => exchangeKey,
          fetcher: fetcher,
          isLive: true,
          autoReconnect: true,
          onReauthenticate: () async {
            reauthCount++;
          },
          reconnectBackoff: testBackoff,
        );
        final client = HttpClient();
        try {
          final request = await client.getUrl(proxy.uri);
          final response = await request.close();
          final (received, _) = await collectAll(response);
          expect(received, isEmpty);
          // Give a misclassified retry two backoff windows to
          // show itself before pinning the attempt count.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(source.attempts, 1);
          expect(reauthCount, 0);
        } finally {
          client.close(force: true);
          await proxy.stop();
          fetcher.close();
          await source.stop();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('an unseekable recording never reconnects: a mid-stream '
        'drop delivers the decrypted prefix and ends', () async {
      final plain = pattern(64 * 1024, 42);
      final wire = buildPcpPacket(
        exchangeKey: exchangeKey,
        label: label,
        encryptionMode: encryptionMode,
        nonce: nonce,
        plaintext: plain,
      );
      final source = ScriptedLiveSource((request, attempt) async {
        if (attempt == 1) {
          await dropMidBody(request, wire, 100);
          return;
        }
        await serveWire(request, wire);
      });
      await source.start();
      final fetcher = DtcpMediaFetcher();
      final proxy = await DtcpProxy.start(
        contentUrl: source.url,
        keyForLabel: (_) async => exchangeKey,
        fetcher: fetcher,
        isLive: false,
        autoReconnect: true,
        onReauthenticate: () async {},
        reconnectBackoff: testBackoff,
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(proxy.uri);
        final response = await request.close();
        final (received, _) = await collectAll(response);
        expect(received.length, greaterThan(0));
        expect(received.length, lessThan(plain.length));
        expect(
          received,
          Uint8List.sublistView(plain, 0, received.length),
          reason:
              'what arrives must be the exact decrypted '
              'prefix, never a restart from byte 0',
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(source.attempts, 1);
      } finally {
        client.close(force: true);
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an unseekable recording ends normally at a clean EOF '
        'without reconnecting', () async {
      final plain = pattern(64 * 1024, 7);
      final wire = buildPcpPacket(
        exchangeKey: exchangeKey,
        label: label,
        encryptionMode: encryptionMode,
        nonce: nonce,
        plaintext: plain,
      );
      final source = ScriptedLiveSource((request, attempt) async {
        await serveWire(request, wire);
      });
      await source.start();
      final fetcher = DtcpMediaFetcher();
      final proxy = await DtcpProxy.start(
        contentUrl: source.url,
        keyForLabel: (_) async => exchangeKey,
        fetcher: fetcher,
        isLive: false,
        autoReconnect: true,
        onReauthenticate: () async {},
        reconnectBackoff: testBackoff,
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(proxy.uri);
        final response = await request.close();
        final (received, error) = await collectAll(response);
        expect(error, isNull);
        expect(received, plain);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(source.attempts, 1);
      } finally {
        client.close(force: true);
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('seekable resume (plan 129)', () {
    const total = 480000; // 20 s at the fake's 24000 B/s.

    Future<(DtcpProxy, DtcpMediaFetcher)> startSeekable(
      DropSeekSource source, {
      required int totalBytes,
      required Duration totalDuration,
      required Future<void> Function() onReauthenticate,
    }) async {
      final fetcher = DtcpMediaFetcher();
      final proxy = await DtcpProxy.start(
        contentUrl: source.url,
        keyForLabel: (_) async => exchangeKey,
        fetcher: fetcher,
        totalBytes: totalBytes,
        totalDuration: totalDuration,
        autoReconnect: true,
        onReauthenticate: onReauthenticate,
        reconnectBackoff: testBackoff,
      );
      return (proxy, fetcher);
    }

    test('a mid-body drop resumes at the reader byte through a 503 '
        'outage, byte-exact, with re-authentication', () async {
      final plain = pattern(total, 17);
      final source =
          DropSeekSource(
              actualPlaintext: plain,
              declaredTotal: total,
              exchangeKey: exchangeKey,
              label: label,
              encryptionMode: encryptionMode,
            )
            ..plainGetDropAfterWireBytes = 200014
            ..timeSeek503Remaining = 2;
      await source.start();
      var reauthCount = 0;
      final (proxy, fetcher) = await startSeekable(
        source,
        totalBytes: total,
        totalDuration: const Duration(seconds: 20),
        onReauthenticate: () async {
          reauthCount++;
        },
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(proxy.uri);
        final response = await request.close();
        final (received, error) = await collectAll(response);
        expect(error, isNull);
        expect(
          received,
          plain,
          reason:
              'the resumed recording must arrive complete '
              'and byte-exact: no gap, no duplicate, no '
              're-served prefix',
        );
        expect(source.timeSeekCount, 3);
        expect(
          source.declaredStarts.last,
          lessThanOrEqualTo(200000),
          reason:
              'the resume must start at or before the drop '
              'point, never past bytes the player is missing',
        );
        expect(reauthCount, greaterThanOrEqualTo(1));
      } finally {
        client.close(force: true);
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a drop followed by a committed refusal (404) ends the '
        'response at the served prefix without a retry storm', () async {
      final plain = pattern(total, 23);
      final source =
          DropSeekSource(
              actualPlaintext: plain,
              declaredTotal: total,
              exchangeKey: exchangeKey,
              label: label,
              encryptionMode: encryptionMode,
            )
            ..plainGetDropAfterWireBytes = 100014
            ..timeSeek404 = true;
      await source.start();
      var reauthCount = 0;
      final (proxy, fetcher) = await startSeekable(
        source,
        totalBytes: total,
        totalDuration: const Duration(seconds: 20),
        onReauthenticate: () async {
          reauthCount++;
        },
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(proxy.uri);
        final response = await request.close();
        final (received, _) = await collectAll(response);
        expect(received.length, greaterThan(0));
        expect(received.length, lessThan(total));
        expect(
          received,
          Uint8List.sublistView(plain, 0, received.length),
          reason:
              'what was served before the refusal stays '
              'the exact prefix; nothing is fabricated',
        );
        expect(source.timeSeekCount, 1);
        expect(reauthCount, 0);
      } finally {
        client.close(force: true);
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a clean end short of the declared total near the end is '
        'the real EOF, and later ranges are bounded by it', () async {
      const declared = 49152;
      final actual = pattern(45056, 31);
      final source = DropSeekSource(
        actualPlaintext: actual,
        declaredTotal: declared,
        exchangeKey: exchangeKey,
        label: label,
        encryptionMode: encryptionMode,
      );
      await source.start();
      final (proxy, fetcher) = await startSeekable(
        source,
        totalBytes: declared,
        totalDuration: const Duration(milliseconds: 2048),
        onReauthenticate: () async {},
      );
      final client = HttpClient();
      try {
        final request = await client.getUrl(proxy.uri);
        final response = await request.close();
        // The response head promised the declared length, so
        // the client may report the short body as an error;
        // the bytes are what matters.
        final (received, _) = await collectAll(response);
        expect(received, actual);
        expect(
          source.timeSeekCount,
          lessThanOrEqualTo(1),
          reason:
              'at most one confirmation restart at the '
              'same byte before the end is declared',
        );
        final rangeRequest = await client.getUrl(proxy.uri);
        rangeRequest.headers.set('range', 'bytes=46000-');
        final rangeResponse = await rangeRequest.close();
        expect(
          rangeResponse.statusCode,
          HttpStatus.requestedRangeNotSatisfiable,
        );
        expect(rangeResponse.headers.value('content-range'), 'bytes */45056');
        await collectAll(rangeResponse);
      } finally {
        client.close(force: true);
        await proxy.stop();
        fetcher.close();
        await source.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('PlaybackKeySource.forceReauthenticate (plan 129)', () {
    test('swaps the session, closes the old one, and serves keys '
        'from the fresh session', () async {
      final first = _FakeKeySession({label: exchangeKey});
      final second = _FakeKeySession({label: exchangeKey});
      var reauthCalls = 0;
      final source = PlaybackKeySource(
        session: first,
        reauthenticate: () async {
          reauthCalls++;
          return second;
        },
      );
      await source.forceReauthenticate();
      expect(reauthCalls, 1);
      // The old session's close is fire-and-forget inside the
      // key source; let it land.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(first.closed, isTrue);
      expect(second.closed, isFalse);
      expect(await source.keyForLabel(label), exchangeKey);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
