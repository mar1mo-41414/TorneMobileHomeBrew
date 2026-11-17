/// Loopback HTTP proxy that feeds decrypted TS to the player.
///
/// Why a proxy (plan 26.3): the player (media_kit / mpv) opens a URL,
/// while the content arrives as an HTTP response whose body is a
/// stream of PCP packets that must be decrypted with the session's
/// exchange key. Serving the decrypted stream from 127.0.0.1 keeps
/// the plaintext in memory end to end — it is never written to a
/// file, which is also the licensing-appropriate handling. The
/// proxy accepts only loopback connections and serves one playback
/// session at a time.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics.dart';
import '../errors.dart';
import 'pcp.dart';

/// Supplies the media response: HEAD/GET against the content URL
/// with the DLNA/DTCP headers the source expects (pydtcpip client).
class DtcpMediaFetcher {
  DtcpMediaFetcher({
    HttpClient Function()? clientFactory,
    this.diag = const DiagLog.none(),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  /// Diagnostics sink (plan 28), category network.
  final DiagLog diag;
  HttpClient? _client;

  HttpClient get _http =>
      _client ??= _clientFactory()
        ..connectionTimeout = const Duration(seconds: 15);

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  /// Issues the HEAD request that reveals the AKE endpoint
  /// (DTCP1HOST / DTCP1PORT content features).
  ///
  /// The Content-Type header is parsed from its RAW value: dart:io
  /// normalizes parameter names to lowercase, so looking up
  /// 'DTCP1HOST' in `ContentType.parameters` never matched and
  /// every playback start failed here in build 6 (plan 28). The
  /// reference client parses the raw header itself; so does this.
  /// The status and the media type are validated like the
  /// reference (a non-200 or a non-DTCP media type is an error,
  /// not an endpoint-less response).
  Future<(String host, int port)> akeEndpoint(Uri contentUrl) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await _http.headUrl(contentUrl);
      _applyHeaders(request);
      final response = await request.close();
      final rawType =
          response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final (mediaType, params) = _parseContentType(rawType);
      final status = response.statusCode;
      await response.drain<void>();
      diag(
        DiagCategory.network,
        'HEAD ${contentUrl.host}:${contentUrl.port} -> $status in '
        '${stopwatch.elapsedMilliseconds} ms; media=$mediaType '
        'params=${params.keys.join(',')}',
      );
      if (status != HttpStatus.ok) {
        throw NasneError.http(status, 'dtcp:http');
      }
      if (mediaType != 'application/x-dtcp1') {
        throw NasneError.parse(
          'dtcp:http',
          cause: 'unexpected content media type: $mediaType',
        );
      }
      final host = params['dtcp1host'];
      final port = int.tryParse(params['dtcp1port'] ?? '');
      if (host == null ||
          host.isEmpty ||
          port == null ||
          port < 1 ||
          port > 65535) {
        throw NasneError.parse(
          'dtcp:http',
          cause: 'the content response carries no DTCP endpoint',
        );
      }
      diag(DiagCategory.network, 'dtcp endpoint: $host:$port');
      return (host, port);
    } on NasneError {
      rethrow;
    } catch (e) {
      // Socket/HTTP failures are reachability failures; classify
      // them so the UI (and the debug log) can name the stage.
      throw NasneError.unreachable('dtcp:http', cause: '$e');
    }
  }

  /// Splits a Content-Type header value into media type and
  /// parameters; parameter names are lowercased (DTCP parameters
  /// are matched case-insensitively, like the reference parser).
  static (String, Map<String, String>) _parseContentType(String value) {
    final parts = value.split(';');
    final mediaType = parts.first.trim().toLowerCase();
    final params = <String, String>{};
    for (final part in parts.skip(1)) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      final name = part.substring(0, eq).trim().toLowerCase();
      var v = part.substring(eq + 1).trim();
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      params[name] = v;
    }
    return (mediaType, params);
  }

  /// Opens the GET response for the same URL (must be the same
  /// endpoint the HEAD was issued against).
  Future<HttpClientResponse> openContent(Uri contentUrl) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await _http.getUrl(contentUrl);
      _applyHeaders(request);
      final response = await request.close();
      diag(
        DiagCategory.network,
        'GET ${contentUrl.host}:${contentUrl.port} -> '
        '${response.statusCode} in ${stopwatch.elapsedMilliseconds} ms, '
        'content-length ${response.contentLength}',
      );
      if (response.statusCode != HttpStatus.ok) {
        throw NasneError.http(response.statusCode, 'dtcp:http');
      }
      return response;
    } on NasneError {
      rethrow;
    } catch (e) {
      throw NasneError.unreachable('dtcp:http', cause: '$e');
    }
  }

  void _applyHeaders(HttpClientRequest request) {
    request.headers.set(
      'transferMode.dlna.org',
      'Streaming',
      preserveHeaderCase: true,
    );
    request.headers.set(
      'getcontentFeatures.dlna.org',
      '1',
      preserveHeaderCase: true,
    );
    request.headers.set('Accept-Encoding', 'identity');
  }
}

/// One playback session's proxy: binds an ephemeral loopback port
/// and serves the decrypted stream at /stream.
///
/// Plan 30 restructure: the content GET starts when the proxy
/// starts (the moment the session reports "playback ready"), not
/// when the player connects, and the decrypted plaintext is
/// prefetch-buffered up to [prefetchCapBytes]. The player-facing
/// response sends its headers immediately on connect and then
/// drains the buffer, so the player sees first bytes as early as
/// the path delivers them — with the streaming decryptor (plan 30)
/// that is the first ciphertext blocks, not the first whole 1 MiB
/// packet. In build 8 the GET waited for the player and the first
/// plaintext waited for a whole packet; over a VPN path the
/// player's ~5 s open timeout fired first.
class DtcpProxy {
  DtcpProxy._(
    this._server,
    this.uri, {
    required Uri contentUrl,
    required Future<Uint8List> Function(int label) keyForLabel,
    required DtcpMediaFetcher fetcher,
    required DiagLog diag,
  }) : _contentUrl = contentUrl, // ignore: prefer_initializing_formals
       _keyForLabel = keyForLabel, // ignore: prefer_initializing_formals
       _fetcher = fetcher, // ignore: prefer_initializing_formals
       _diag = diag; // ignore: prefer_initializing_formals

  final HttpServer _server;

  /// The URL to hand to the player.
  final Uri uri;

  final Uri _contentUrl;
  final Future<Uint8List> Function(int label) _keyForLabel;
  final DtcpMediaFetcher _fetcher;
  final DiagLog _diag;

  final _PlaintextQueue _queue = _PlaintextQueue();
  int _cipherBytes = 0;
  int _servedBytes = 0;
  int _requestCount = 0;
  bool _claimed = false;
  bool _stopRequested = false;
  bool _downstreamGone = false;
  StreamIterator<List<int>>? _iterator;
  Future<void>? _pumpFuture;

  /// How long the content stream may go without a single byte
  /// before the proxy gives up (plan 29). The reference client
  /// applies its 30 s timeout as the socket read timeout; an
  /// unbounded wait here left the player spinning forever.
  static const Duration stallTimeout = Duration(seconds: 30);

  /// Prefetch bound: the pump pauses upstream reads while this
  /// much decrypted plaintext is waiting for the player. Bounds
  /// memory and paces the upstream to the player's consumption
  /// (plan 30).
  static const int prefetchCapBytes = 16 * 1024 * 1024;

  static Future<DtcpProxy> start({
    required Uri contentUrl,
    required Future<Uint8List> Function(int label) keyForLabel,
    required DtcpMediaFetcher fetcher,
    DiagLog diag = const DiagLog.none(),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = DtcpProxy._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/stream'),
      contentUrl: contentUrl,
      keyForLabel: keyForLabel,
      fetcher: fetcher,
      diag: diag,
    );
    server.listen(proxy._handle);
    // Prefetch: the content GET and decryption begin now, while
    // the caller is still handing the URL to the player.
    proxy._pumpFuture = proxy._pump();
    return proxy;
  }

  /// Pulls the content, decrypts it incrementally and queues the
  /// plaintext for the player. Runs from [start] until the
  /// upstream ends, fails, or the session is stopped.
  Future<void> _pump() async {
    final stopwatch = Stopwatch()..start();
    var packets = 0;
    var plainBytes = 0;
    var lastMilestone = 0;
    var firstPlainLogged = false;
    String endKind;
    try {
      _diag(
        DiagCategory.playback,
        'proxy: prefetch started, content GET started',
      );
      final response = await _fetcher.openContent(_contentUrl);
      final decryptor = PcpDecryptor(keyForLabel: _keyForLabel);
      final timed = response.timeout(
        stallTimeout,
        onTimeout: (sink) {
          sink.addError(
            NasneError.unreachable(
              'dtcp:proxy',
              cause:
                  'the content stream stalled for '
                  '${stallTimeout.inSeconds} seconds',
            ),
          );
          sink.close();
        },
      );
      final iterator = StreamIterator<List<int>>(timed);
      _iterator = iterator;
      try {
        while (!_stopRequested) {
          if (_queue.bufferedBytes >= prefetchCapBytes) {
            await _waitForDrain();
            continue;
          }
          if (!await iterator.moveNext()) break;
          final chunk = iterator.current;
          _cipherBytes += chunk.length;
          final pieces = await decryptor.add(chunk);
          packets = decryptor.packetsDecrypted;
          plainBytes = decryptor.plaintextBytes;
          for (final piece in pieces) {
            if (!firstPlainLogged) {
              firstPlainLogged = true;
              _diag(
                DiagCategory.playback,
                'proxy: first plaintext out, ${piece.length} bytes, '
                '${stopwatch.elapsedMilliseconds} ms after the '
                'content GET',
              );
            }
            _queue.add(piece);
          }
          if (packets > lastMilestone && (packets == 1 || packets % 50 == 0)) {
            lastMilestone = packets;
            _diag(
              DiagCategory.playback,
              'proxy: $packets packets, $plainBytes bytes decrypted '
              'so far',
            );
          }
        }
      } finally {
        await iterator.cancel();
      }
      endKind = _downstreamGone
          ? 'stopped (the player went away)'
          : _stopRequested
          ? 'stopped (session end)'
          : 'the upstream ended the stream';
      _queue.close();
      _diag(
        DiagCategory.playback,
        'proxy: stream ended: $endKind; received $_cipherBytes '
        'bytes, decrypted $plainBytes bytes in $packets packets, '
        '${stopwatch.elapsedMilliseconds} ms after the content GET, '
        'player ${_claimed ? 'attached' : 'never connected'}',
      );
    } catch (e) {
      _queue.close(e);
      _diag(
        DiagCategory.playback,
        'proxy: upstream closed with an error after $_cipherBytes '
        'bytes received, $plainBytes bytes decrypted in $packets '
        'packets, ${stopwatch.elapsedMilliseconds} ms after the '
        'content GET: $e',
      );
    }
  }

  /// Waits while the prefetch buffer is at the cap, until the
  /// player drains some of it or the session stops.
  Future<void> _waitForDrain() async {
    while (!_stopRequested &&
        !_queue.isClosed &&
        _queue.bufferedBytes >= prefetchCapBytes) {
      await _queue.waitChange();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != '/stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    _requestCount++;
    final requestNo = _requestCount;
    if (_claimed) {
      _diag(
        DiagCategory.playback,
        'proxy: request #$requestNo rejected; the stream is '
        'already claimed',
      );
      request.response.statusCode = HttpStatus.conflict;
      await request.response.close();
      return;
    }
    _claimed = true;
    _diag(DiagCategory.playback, 'proxy: request #$requestNo from the player');
    final response = request.response;
    // The pump already failed before producing anything: fail
    // fast instead of opening a stream that only errors later.
    if (_queue.isClosed && _queue.bufferedBytes == 0 && _queue.hasError) {
      _diag(
        DiagCategory.playback,
        'proxy: the content fetch had already failed; answering 502',
      );
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType('video', 'mp2t');
    response.headers.set('transferMode.dlna.org', 'Streaming');
    try {
      // Headers go out immediately; the first plaintext follows
      // as soon as the pump produces it (prefetched or live).
      await response.flush();
      while (true) {
        final chunk = await _queue.read();
        if (chunk == null) break;
        _servedBytes += chunk.length;
        response.add(chunk);
        await response.flush();
      }
      await response.close();
      _diag(
        DiagCategory.playback,
        'proxy: player stream completed, $_servedBytes bytes served',
      );
    } catch (e) {
      _diag(
        DiagCategory.playback,
        'proxy: serving ended with an error after $_servedBytes '
        'bytes served: $e',
      );
      // The player is gone (or the upstream failed through the
      // queue): stop pulling the content.
      _downstreamGone = true;
      _stopRequested = true;
      _queue.close();
      await _iterator?.cancel();
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    _queue.close();
    await _iterator?.cancel();
    await _server.close(force: true);
    final pump = _pumpFuture;
    if (pump != null) {
      // The pump observes the stop through the flags above; do
      // not let teardown hang on it.
      await pump.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
  }
}

/// Bounded FIFO of decrypted plaintext between the pump and the
/// player-facing response. One producer (the pump), one consumer
/// (the response handler). Waiters are woken through a shared
/// change signal and re-check their own condition.
class _PlaintextQueue {
  final List<Uint8List> _chunks = [];
  int _bufferedBytes = 0;
  bool _closed = false;
  Object? _error;
  bool _errorDelivered = false;
  Completer<void>? _changed;

  int get bufferedBytes => _bufferedBytes;
  bool get isClosed => _closed;
  bool get hasError => _error != null;

  void add(Uint8List chunk) {
    if (_closed || chunk.isEmpty) return;
    _chunks.add(chunk);
    _bufferedBytes += chunk.length;
    _notify();
  }

  /// Ends the queue. A stored [error] is delivered to the reader
  /// once the buffered plaintext has drained.
  void close([Object? error]) {
    if (_closed) return;
    _closed = true;
    if (error != null) _error = error;
    _notify();
  }

  /// The next plaintext chunk, or null at a clean end of stream.
  /// Throws the pump's error once, after the buffer has drained.
  Future<Uint8List?> read() async {
    while (true) {
      if (_chunks.isNotEmpty) {
        final piece = _chunks.removeAt(0);
        _bufferedBytes -= piece.length;
        _notify();
        return piece;
      }
      if (_closed) {
        final error = _error;
        if (error != null && !_errorDelivered) {
          _errorDelivered = true;
          throw error;
        }
        return null;
      }
      await waitChange();
    }
  }

  /// Completes at the next add / consume / close.
  Future<void> waitChange() {
    final completer = _changed ??= Completer<void>();
    return completer.future;
  }

  void _notify() {
    final completer = _changed;
    _changed = null;
    completer?.complete();
  }
}
