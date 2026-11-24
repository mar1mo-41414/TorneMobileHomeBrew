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
///
/// Plan 61 adds a SEEKABLE mode for recorded content whose total
/// plaintext size (DIDL `dlna:cleartextSize`) and duration are
/// known. The nasne content endpoint refuses byte ranges outright
/// (HTTP 406, measured 2026-11-17), but it implements the DLNA
/// time seek: a GET with `TimeSeekRange.dlna.org: npt=<t>-` starts
/// the PCP stream at the source's own byte position for time t,
/// declared in the response's TimeSeekRange header (the start byte
/// is MPEG-TTS aligned, and PCP framing restarts there, so
/// decryption always begins at a packet boundary). The proxy
/// therefore advertises byte ranges to the player and translates
/// each requested byte offset into a time seek upstream: it asks
/// for a slightly earlier time, learns the source's time<->byte
/// map from every response, decrypts from the returned start byte
/// and discards forward to the exact requested offset. Live
/// content (no known end) keeps the original unseekable behaviour.
///
/// Plan 129 adds automatic recovery from upstream drops, enabled
/// by the engine on Android (other platforms keep the behaviour
/// above exactly). The motivating environment is plan 126's
/// unstable link — in a car, over tethering or a VPN path —
/// where a drop longer than any reasonable bank is a matter of
/// when, not if, so banking alone cannot be the whole answer.
/// Live streams reconnect with backoff and a fresh
/// authentication; seekable recordings resume the producer at
/// the byte the reader has reached. A failure the source
/// answered with a committed refusal (a non-transient HTTP
/// status, a parse failure) is NOT retried: reissuing the
/// identical request cannot succeed, and the error surfaces as
/// it always has.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../diagnostics.dart';
import '../errors.dart';
import 'ake.dart';
import 'pcp.dart';

/// The source's answer to a time-seek content request (plan 61):
/// the open response plus the mapping the source declared in its
/// `TimeSeekRange.dlna.org` response header.
class TimeSeekResponse {
  const TimeSeekResponse({
    required this.response,
    required this.startByte,
    this.startSeconds,
    this.totalBytes,
    this.totalSeconds,
  });

  /// The response body: PCP ciphertext whose plaintext begins at
  /// [startByte].
  final HttpClientResponse response;

  /// Plaintext offset of the first byte of [response] (the `bytes=`
  /// start of the source's TimeSeekRange header). 0 when the source
  /// sent no mapping header (it ignored the seek).
  final int startByte;

  /// The npt start the source reports, when it sent one.
  final double? startSeconds;

  /// The source-reported total plaintext size, when sent.
  final int? totalBytes;

  /// The source-reported total duration, when sent.
  final double? totalSeconds;
}

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

  /// Drops the underlying client and every pooled socket, so
  /// the next request opens a fresh TCP connection. A reconnect
  /// after a network drop must not be handed a half-open pooled
  /// socket (plan 129).
  void resetClient() {
    _client?.close(force: true);
    _client = null;
  }

  void close() => resetClient();

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

  static final RegExp _timeSeekNptPattern = RegExp(
    r'npt=([0-9.]+)-([0-9.]+)/([0-9.]+)',
  );
  static final RegExp _timeSeekBytesPattern = RegExp(
    r'bytes=(\d+)-(\d+)/(\d+)',
  );

  /// Opens the GET response for a DLNA time seek (plan 61): the
  /// source starts the PCP stream at its own byte position for
  /// [seconds] and declares the mapping in the response's
  /// TimeSeekRange header, e.g.
  /// `npt=600.000-1818.000/1818.000 bytes=1080013440-3246817151/3246817152`.
  ///
  /// A source that does not implement the time seek answers 406
  /// (measured on the nasne for byte Range and for res URLs that
  /// do not exist); that surfaces as a [NasneError] with category
  /// http and code '406', and the caller decides the fallback.
  Future<TimeSeekResponse> openContentAtTime(
    Uri contentUrl,
    double seconds,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await _http.getUrl(contentUrl);
      _applyHeaders(request);
      request.headers.set(
        'TimeSeekRange.dlna.org',
        'npt=${seconds.toStringAsFixed(3)}-',
        preserveHeaderCase: true,
      );
      final response = await request.close();
      diag(
        DiagCategory.network,
        'GET (time seek npt=${seconds.toStringAsFixed(3)}) '
        '${contentUrl.host}:${contentUrl.port} -> '
        '${response.statusCode} in ${stopwatch.elapsedMilliseconds} ms',
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw NasneError.http(response.statusCode, 'dtcp:http');
      }
      final header = response.headers.value('timeseekrange.dlna.org');
      final npt = header == null
          ? null
          : _timeSeekNptPattern.firstMatch(header);
      final bytes = header == null
          ? null
          : _timeSeekBytesPattern.firstMatch(header);
      if (npt == null || bytes == null) {
        // The source ignored the seek and is streaming from 0.
        diag(
          DiagCategory.network,
          'time seek: no mapping header in the response; '
          'assuming a stream from byte 0',
        );
        return TimeSeekResponse(response: response, startByte: 0);
      }
      final startByte = int.parse(bytes.group(1)!);
      final startSeconds = double.parse(npt.group(1)!);
      diag(
        DiagCategory.network,
        'time seek: source maps npt $startSeconds to byte '
        '$startByte (total ${bytes.group(3)} bytes / '
        '${npt.group(3)} s)',
      );
      return TimeSeekResponse(
        response: response,
        startByte: startByte,
        startSeconds: startSeconds,
        totalBytes: int.parse(bytes.group(3)!),
        totalSeconds: double.parse(npt.group(3)!),
      );
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
///
/// Plan 61: with [totalBytes] and [totalDuration] supplied the
/// proxy runs in seekable mode instead (see the library comment);
/// the prefetch then fills a plaintext window cache that ranged
/// requests read from, and seeks are produced by time-seek
/// pipelines. Without them the original single-stream behaviour
/// above is kept exactly (live content).
class DtcpProxy {
  DtcpProxy._(
    this._server,
    this.uri, {
    required Uri contentUrl,
    required Future<Uint8List> Function(int label) keyForLabel,
    required DtcpMediaFetcher fetcher,
    required DiagLog diag,
    int? totalBytes,
    Duration? totalDuration,
    int? windowCapBytesOverride,
    int? prefetchCapBytesOverride,
    bool isLive = false,
    bool autoReconnect = false,
    Future<void> Function()? onReauthenticate,
    List<Duration> reconnectBackoff = defaultReconnectBackoff,
  }) : _window = _WindowCache(
         capBytes: windowCapBytesOverride ?? windowCapBytes,
       ),
       _prefetchCapBytes = prefetchCapBytesOverride ?? prefetchCapBytes,
       _contentUrl = contentUrl, // ignore: prefer_initializing_formals
       _keyForLabel = keyForLabel, // ignore: prefer_initializing_formals
       _fetcher = fetcher, // ignore: prefer_initializing_formals
       _diag = diag, // ignore: prefer_initializing_formals
       _totalBytes = totalBytes, // ignore: prefer_initializing_formals
       _totalDuration = totalDuration, // ignore: prefer_initializing_formals
       _isLive = isLive, // ignore: prefer_initializing_formals
       _autoReconnect = autoReconnect, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _onReauthenticate = onReauthenticate,
       // ignore: prefer_initializing_formals
       _reconnectBackoff = reconnectBackoff;

  final HttpServer _server;

  /// The URL to hand to the player.
  final Uri uri;

  final Uri _contentUrl;
  final Future<Uint8List> Function(int label) _keyForLabel;
  final DtcpMediaFetcher _fetcher;
  final DiagLog _diag;

  /// Whether the content is a live stream (plan 129): a live
  /// upstream that ends has DROPPED — a live stream has no end
  /// of its own — while a recording's upstream ending is its
  /// end.
  final bool _isLive;

  /// Whether upstream drops are recovered automatically
  /// (plan 129). Enabled by the engine on Android only; with
  /// it off, every path below behaves exactly as before.
  final bool _autoReconnect;

  /// Forces a fresh AKE authentication ahead of a reconnect
  /// attempt when the failure suggests the old session went
  /// stale (plan 129). Supplied by the engine; null when
  /// [_autoReconnect] is off.
  final Future<void> Function()? _onReauthenticate;

  /// The backoff ladder for reconnect attempts (plan 129).
  final List<Duration> _reconnectBackoff;

  /// Total plaintext size in bytes (recorded content only).
  final int? _totalBytes;

  /// Total content duration (recorded content only).
  final Duration? _totalDuration;

  /// Seekable mode (plan 61) requires both the size and the
  /// duration: the size is the advertised content length, the
  /// duration drives the byte->time conversion.
  /// The prefetch queue bound in force (plan 126).
  int get prefetchCapBytesInForce => _prefetchCapBytes;

  /// The seekable window bound in force (plan 126).
  int get windowCapBytesInForce => _window.capBytes;

  bool get _seekable =>
      _totalBytes != null &&
      _totalBytes > 0 &&
      _totalDuration != null &&
      _totalDuration > Duration.zero;

  final _PlaintextQueue _queue = _PlaintextQueue();

  /// The prefetch bound in force for this proxy: the caller's
  /// override (the playback buffer setting, plan 126) or the
  /// long-standing [prefetchCapBytes].
  final int _prefetchCapBytes;
  int _cipherBytes = 0;
  int _servedBytes = 0;
  int _requestCount = 0;
  bool _claimed = false;
  bool _stopRequested = false;
  bool _downstreamGone = false;
  StreamIterator<List<int>>? _iterator;
  Future<void>? _pumpFuture;

  // Seekable-mode state (plan 61).
  final _WindowCache _window;
  _SeekMap? _seekMap;
  _Producer? _producer;
  int _serveGeneration = 0;

  /// The upstream's real end, once a clean end short of the
  /// declared total has been confirmed as the content's EOF
  /// (plan 129). Only ever set with auto-reconnect on; while
  /// null, requests are bounded by the declared total alone,
  /// as before.
  int? _eofByte;

  /// How long the content stream may go without a single byte
  /// before the proxy gives up (plan 29). The reference client
  /// applies its 30 s timeout as the socket read timeout; an
  /// unbounded wait here left the player spinning forever.
  static const Duration stallTimeout = Duration(seconds: 30);

  /// Backoff ladder for automatic reconnect attempts
  /// (plan 129): the delay before the attempt following N
  /// consecutive failures is entry N, clamped at the last
  /// entry, so a long outage settles into a 10 s rhythm
  /// instead of hammering the source.
  static const List<Duration> defaultReconnectBackoff = [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 10),
  ];

  /// How close to the declared total a clean upstream end may
  /// land and still be taken as the content's real end
  /// (plan 129): the declared cleartext size can overstate the
  /// actual stream by a small tail, and re-asking at that
  /// point only reproduces the same end.
  static const int eofSlackBytes = 2 * 1024 * 1024;

  /// Prefetch bound: the pump pauses upstream reads while this
  /// much decrypted plaintext is waiting for the player. Bounds
  /// memory and paces the upstream to the player's consumption
  /// (plan 30).
  static const int prefetchCapBytes = 16 * 1024 * 1024;

  /// Plaintext window bound in seekable mode (plan 61): how much
  /// decrypted plaintext is retained behind/ahead of the reader,
  /// which is what makes short backward seeks instant.
  static const int windowCapBytes = 32 * 1024 * 1024;

  /// How far before the estimated time a seek request aims, so
  /// the source's start byte lands at or before the target and
  /// the difference is discarded after decryption (plan 61). The
  /// learned map keeps the overshoot small; the retry loop covers
  /// the rest.
  static const double seekMarginSeconds = 2.0;

  /// Time-seek attempts per producer before serving from the
  /// source's start byte as a last resort (plan 61).
  static const int maxSeekAttempts = 4;

  /// How long a ranged request waits for its seek pipeline to
  /// establish before failing (plan 61).
  static const Duration seekEstablishTimeout = Duration(seconds: 30);

  /// Upper bound on one pause wait in the seekable pump
  /// (plan 80): a backstop so a producer paused on the window
  /// cap re-evaluates its condition periodically even if a
  /// notification was missed.
  static const Duration pumpPauseWaitCap = Duration(seconds: 5);

  /// How many times one content open retries the source's
  /// transient refusal (HTTP 512) before the refusal is
  /// treated as final (plan 80; the refusal itself is
  /// analysed in plan 78.3).
  static const int maxBusyRetries = 3;

  /// Backoff between those retries, by retry number.
  static const List<Duration> busyRetryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  static Future<DtcpProxy> start({
    required Uri contentUrl,
    required Future<Uint8List> Function(int label) keyForLabel,
    required DtcpMediaFetcher fetcher,
    DiagLog diag = const DiagLog.none(),
    int? totalBytes,
    Duration? totalDuration,
    int? windowCapBytesOverride,
    int? prefetchCapBytesOverride,
    bool isLive = false,
    bool autoReconnect = false,
    Future<void> Function()? onReauthenticate,
    List<Duration> reconnectBackoff = defaultReconnectBackoff,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = DtcpProxy._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/stream'),
      contentUrl: contentUrl,
      keyForLabel: keyForLabel,
      fetcher: fetcher,
      diag: diag,
      totalBytes: totalBytes,
      totalDuration: totalDuration,
      windowCapBytesOverride: windowCapBytesOverride,
      prefetchCapBytesOverride: prefetchCapBytesOverride,
      isLive: isLive,
      autoReconnect: autoReconnect,
      onReauthenticate: onReauthenticate,
      reconnectBackoff: reconnectBackoff,
    );
    server.listen(proxy._handle);
    diag(
      DiagCategory.playback,
      'proxy: buffer caps in force: prefetch '
      '${proxy.prefetchCapBytesInForce} bytes, window '
      '${proxy.windowCapBytesInForce} bytes',
    );
    if (proxy._seekable) {
      proxy._seekMap = _SeekMap(
        totalBytes: totalBytes!,
        totalSeconds: totalDuration!.inMicroseconds / 1e6,
      );
      diag(
        DiagCategory.playback,
        'proxy: seekable mode, $totalBytes bytes / $totalDuration',
      );
      // Prefetch from byte 0, as in the original design.
      proxy._startProducer(0);
    } else {
      // Prefetch: the content GET and decryption begin now, while
      // the caller is still handing the URL to the player.
      proxy._pumpFuture = proxy._pump();
    }
    return proxy;
  }

  /// Whether reissuing the identical content request after a
  /// backoff can plausibly succeed (plan 129): the link failed
  /// (unreachable-class errors, which is how the fetcher and
  /// the AKE layer report socket failures and stalls), or the
  /// source answered with a transient status — server-side
  /// 5xx, 408, the 512 busy refusal the open path already
  /// retries (plan 80), and 401/403, which pair with the
  /// forced re-authentication in [_shouldReauthenticate].
  /// Everything else — a refusal the device committed to
  /// (404/406/416 and the other 4xx), a parse or validation
  /// failure — cannot be fixed by asking again and surfaces
  /// as it always has.
  static bool _isTransientReconnectError(Object error) {
    if (error is NasneError) {
      if (error.category == NasneErrorCategory.unreachable) return true;
      if (error.category == NasneErrorCategory.http) {
        return const {
          '401',
          '403',
          '408',
          '500',
          '502',
          '503',
          '504',
          '512',
        }.contains(error.code);
      }
      return false;
    }
    // Raw network-layer failures that reach the pumps without
    // classification: a destroyed upstream socket surfaces as
    // an HttpException, a key wait across an outage as a
    // TimeoutException or as the ended AKE session.
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is AkeConnectionClosed;
  }

  /// Whether a reconnect attempt should first force a fresh
  /// AKE authentication (plan 129): the failure itself names
  /// authentication or server state (401/403/500/503/512), or
  /// failures are repeating — the second consecutive failure
  /// re-authenticates even when each looked purely network,
  /// because after a long outage the source-side session is
  /// the prime suspect.
  static bool _shouldReauthenticate(Object? error, int consecutiveErrors) {
    if (consecutiveErrors >= 2) return true;
    if (error is NasneError && error.category == NasneErrorCategory.http) {
      return const {'401', '403', '500', '503', '512'}.contains(error.code);
    }
    return false;
  }

  /// The backoff before the reconnect attempt that follows
  /// [failures] consecutive failures, clamped at the ladder's
  /// last entry.
  Duration _backoffForAttempt(int failures) {
    if (_reconnectBackoff.isEmpty) return Duration.zero;
    return _reconnectBackoff[min(failures, _reconnectBackoff.length - 1)];
  }

  /// Runs [_onReauthenticate] for a reconnect attempt, logging
  /// rather than propagating a failure: the attempt itself is
  /// the next step either way, and its own failure feeds the
  /// same backoff ladder.
  Future<void> _reauthenticateForReconnect(String what) async {
    try {
      await _onReauthenticate?.call();
    } catch (e) {
      _diag(
        DiagCategory.playback,
        'proxy: re-authentication before the $what reconnect failed: $e',
      );
    }
  }

  /// Pulls the content, decrypts it incrementally and queues the
  /// plaintext for the player. Runs from [start] until the
  /// upstream ends, fails, or the session is stopped.
  ///
  /// Plan 129: with auto-reconnect on and live content, an
  /// upstream drop — a transient error, or an end, which a live
  /// stream never reaches on its own — is retried with backoff
  /// until the session stops or the player goes away. The queue
  /// stays open across attempts, so the player sees one
  /// continuous stream (and a stall while the link is down,
  /// absorbed by the plan-126 bank). Every other combination
  /// keeps the single-attempt behaviour exactly: in particular
  /// an unseekable recording is never restarted, because its
  /// stream cannot resume mid-way and a fresh GET would serve
  /// it again from byte 0 into the same queue, corrupting what
  /// the player receives.
  Future<void> _pump() async {
    final stopwatch = Stopwatch()..start();
    var packets = 0;
    var plainBytes = 0;
    var lastMilestone = 0;
    var firstPlainLogged = false;
    var consecutiveErrors = 0;

    void logEnd(String endKind) {
      _diag(
        DiagCategory.playback,
        'proxy: stream ended: $endKind; received $_cipherBytes '
        'bytes, decrypted $plainBytes bytes in $packets packets, '
        '${stopwatch.elapsedMilliseconds} ms after the content GET, '
        'player ${_claimed ? 'attached' : 'never connected'}',
      );
    }

    void logError(Object e) {
      _diag(
        DiagCategory.playback,
        'proxy: upstream closed with an error after $_cipherBytes '
        'bytes received, $plainBytes bytes decrypted in $packets '
        'packets, ${stopwatch.elapsedMilliseconds} ms after the '
        'content GET: $e',
      );
    }

    while (true) {
      Object? attemptError;
      var unexpectedEof = false;
      final basePackets = packets;
      final basePlainBytes = plainBytes;
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
            if (_queue.bufferedBytes >= _prefetchCapBytes) {
              await _waitForDrain();
              continue;
            }
            if (!await iterator.moveNext()) {
              if (_autoReconnect && _isLive && !_stopRequested) {
                unexpectedEof = true;
              }
              break;
            }
            final chunk = iterator.current;
            _cipherBytes += chunk.length;
            final pieces = await decryptor.add(chunk);
            packets = basePackets + decryptor.packetsDecrypted;
            plainBytes = basePlainBytes + decryptor.plaintextBytes;
            for (final piece in pieces) {
              consecutiveErrors = 0;
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
            if (packets > lastMilestone &&
                (packets == 1 || packets % 50 == 0)) {
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
          if (identical(_iterator, iterator)) _iterator = null;
        }
      } catch (e) {
        attemptError = e;
      }

      // An error the reconnect machinery will not (or must not)
      // absorb surfaces exactly as it did before plan 129.
      if (attemptError != null &&
          !(_autoReconnect &&
              _isLive &&
              !_stopRequested &&
              !_downstreamGone &&
              _isTransientReconnectError(attemptError))) {
        _queue.close(attemptError);
        logError(attemptError);
        return;
      }
      if (_stopRequested || _downstreamGone) {
        _queue.close();
        logEnd(
          _downstreamGone
              ? 'stopped (the player went away)'
              : 'stopped (session end)',
        );
        return;
      }
      if (attemptError == null && !unexpectedEof) {
        _queue.close();
        logEnd('the upstream ended the stream');
        return;
      }
      // A live drop: back off, drop the fetcher's pooled
      // sockets, re-authenticate when the failure points at
      // the session, and pull again.
      final delay = _backoffForAttempt(consecutiveErrors);
      consecutiveErrors++;
      _diag(
        DiagCategory.playback,
        'proxy: live upstream dropped '
        '(${attemptError ?? 'the stream ended'}); reconnect '
        'attempt $consecutiveErrors after ${delay.inMilliseconds} ms',
      );
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (_stopRequested || _downstreamGone) {
        _queue.close();
        return;
      }
      _fetcher.resetClient();
      if (_shouldReauthenticate(attemptError, consecutiveErrors)) {
        await _reauthenticateForReconnect('live');
      }
    }
  }

  /// Waits while the prefetch buffer is at the cap, until the
  /// player drains some of it or the session stops.
  Future<void> _waitForDrain() async {
    while (!_stopRequested &&
        !_queue.isClosed &&
        _queue.bufferedBytes >= _prefetchCapBytes) {
      await _queue.waitChange();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.uri.path != '/stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (_seekable) {
      await _handleSeekable(request);
    } else {
      await _handleLegacy(request);
    }
  }

  Future<void> _handleLegacy(HttpRequest request) async {
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
    final producer = _producer;
    _cancelProducer();
    _window.close();
    await _iterator?.cancel();
    await _server.close(force: true);
    final pump = _pumpFuture;
    if (pump != null) {
      // The pump observes the stop through the flags above; do
      // not let teardown hang on it.
      await pump.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    if (producer != null) {
      await producer.runFuture?.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    }
  }

  // ----------------------------------------------------------------
  // Seekable mode (plan 61)
  // ----------------------------------------------------------------

  /// Starts the (single) producer pipeline that decrypts into the
  /// window starting exactly at [anchor]. Any previous producer
  /// must already be cancelled.
  _Producer _startProducer(int anchor) {
    final producer = _Producer(anchor);
    _producer = producer;
    // The primer's establishment may never be awaited; keep an
    // error completion from surfacing as an unhandled error.
    unawaited(producer.established.future.then((_) {}, onError: (_) {}));
    _window.anchor(anchor);
    producer.runFuture = _runProducer(producer);
    return producer;
  }

  void _cancelProducer() {
    final producer = _producer;
    if (producer == null) return;
    _producer = null;
    producer.cancelled = true;
    producer.failEstablish(StateError('the producer was superseded'));
    final iterator = producer.iterator;
    if (iterator != null) unawaited(iterator.cancel());
    _window.notify();
  }

  /// Throws [response] away WITHOUT reading it to the end
  /// (plan 80). The discard used to drain: an overshoot
  /// response's remainder can be gigabytes (plan 78.3
  /// measured a ~3.27 GB one), and while it drains the
  /// source's stream slot stays occupied — one of the
  /// conditions behind the HTTP 512 refusals. Cancelling the
  /// subscription closes the connection and frees the slot
  /// at once.
  static Future<void> _discardResponse(HttpClientResponse response) async {
    try {
      await response.listen((_) {}, onError: (_) {}).cancel();
    } catch (_) {
      // The stream is being thrown away either way.
    }
  }

  /// Whether [error] is the source's transient refusal
  /// (HTTP 512, plan 78.3): the source declines a new stream
  /// while earlier responses from this session are still
  /// being reaped on its side, so a short backoff and a
  /// retry succeed where an immediate retry does not.
  static bool _isBusyRefusal(Object error) =>
      error is NasneError &&
      error.category == NasneErrorCategory.http &&
      error.code == '512';

  /// Runs [open] with backoff retries on the transient
  /// refusal (plan 80), rethrowing anything else — and the
  /// refusal itself once the retries are spent — to the
  /// caller's existing fallback logic.
  Future<T> _openWithBusyRetry<T>(
    _Producer producer,
    Future<T> Function() open,
    String what,
  ) async {
    var retries = 0;
    while (true) {
      try {
        return await open();
      } on NasneError catch (e) {
        if (!_isBusyRefusal(e) ||
            retries >= maxBusyRetries ||
            producer.cancelled ||
            _stopRequested) {
          rethrow;
        }
        final delay = busyRetryDelays[retries];
        retries++;
        _diag(
          DiagCategory.playback,
          'proxy: $what refused with 512; retry $retries of '
          '$maxBusyRetries after a ${delay.inMilliseconds} ms '
          'backoff',
        );
        await Future<void>.delayed(delay);
        if (producer.cancelled || _stopRequested) {
          throw StateError('the producer was superseded');
        }
      }
    }
  }

  /// A producer's life: establish where its plaintext starts
  /// (time seek with corrections, or a plain GET for offset 0),
  /// then decrypt into the window until the upstream ends, the
  /// producer is cancelled, or the session stops.
  Future<void> _runProducer(_Producer producer) async {
    final target = producer.anchor;
    final stopwatch = Stopwatch()..start();
    try {
      var attempts = 0;
      var fellBackToPlain = false;
      while (!producer.cancelled && !_stopRequested) {
        attempts++;
        final HttpClientResponse response;
        final int startByte;
        if (target == 0 || fellBackToPlain) {
          response = await _openWithBusyRetry(
            producer,
            () => _fetcher.openContent(_contentUrl),
            'a plain GET',
          );
          startByte = 0;
        } else {
          final map = _seekMap!;
          final estimated = map.timeForByte(target);
          var requested = estimated - seekMarginSeconds;
          if (requested < 0) requested = 0;
          final TimeSeekResponse tsr;
          try {
            tsr = await _openWithBusyRetry(
              producer,
              () => _fetcher.openContentAtTime(_contentUrl, requested),
              'a time seek',
            );
          } on NasneError catch (e) {
            if (_autoReconnect &&
                !(e.category == NasneErrorCategory.http && e.code == '406')) {
              // In reconnect mode the serving loop owns retries
              // (plan 129): a transient refusal is retried there
              // with backoff and re-authentication, and a
              // committed refusal (404 and friends) must surface
              // as itself. Collapsing either into the plain-GET
              // fallback here would mask the refusal behind the
              // fallback's own failures and re-pull the whole
              // recording from byte 0 on every blip. The one
              // refusal the fallback exists for — 406, the
              // measured time-seek refusal mode — still falls
              // back.
              rethrow;
            }
            // A source that refuses the time seek still serves
            // the plain stream; fetch-and-discard from 0 is slow
            // but correct, and keeps playback working.
            _diag(
              DiagCategory.playback,
              'proxy: time seek refused ($e); falling back to a '
              'plain GET for byte $target',
            );
            fellBackToPlain = true;
            continue;
          }
          startByte = tsr.startByte;
          final startSeconds = tsr.startSeconds;
          if (startSeconds != null) {
            map.learn(startSeconds, startByte);
          }
          _diag(
            DiagCategory.playback,
            'proxy: seek target byte $target -> npt '
            '${requested.toStringAsFixed(3)} s; the source starts '
            'at byte $startByte (attempt $attempts)',
          );
          if (startByte > target && attempts < maxSeekAttempts) {
            unawaited(_discardResponse(tsr.response));
            continue;
          }
          response = tsr.response;
        }
        if (producer.cancelled || _stopRequested) {
          unawaited(_discardResponse(response));
          return;
        }
        // The stream start is now fixed: normally the target
        // itself (the difference is discarded after decryption);
        // as a last resort, after repeated overshoots, the
        // source's own start byte.
        final serveStart = startByte > target ? startByte : target;
        if (serveStart != target) {
          _diag(
            DiagCategory.playback,
            'proxy: seek could not land at or before byte $target; '
            'serving from the source start byte $serveStart',
          );
          _window.anchor(serveStart);
        }
        producer.finishEstablish(serveStart);
        await _pumpIntoWindow(
          producer,
          response,
          skipPlaintext: serveStart - startByte,
          stopwatch: stopwatch,
        );
        return;
      }
    } catch (e) {
      producer.error = e;
      producer.failEstablish(e);
      _diag(
        DiagCategory.playback,
        'proxy: producer for byte $target failed: $e',
      );
    } finally {
      producer.finished = true;
      _window.notify();
    }
  }

  /// Decrypts [response] into the window, dropping the first
  /// [skipPlaintext] plaintext bytes (the difference between the
  /// source's start byte and the serve start).
  Future<void> _pumpIntoWindow(
    _Producer producer,
    HttpClientResponse response, {
    required int skipPlaintext,
    required Stopwatch stopwatch,
  }) async {
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
    producer.iterator = iterator;
    var skip = skipPlaintext;
    var produced = 0;
    var firstPlainLogged = false;
    try {
      while (!producer.cancelled && !_stopRequested) {
        if (_window.producerShouldPause) {
          // Bounded wait (plan 80): the pin generation rules
          // should keep a missed notification from mattering,
          // but the pause must never be able to outlive its
          // reason — re-check the condition at least this
          // often instead of waiting for a change that may
          // already have happened.
          await _window.waitChange().timeout(
            pumpPauseWaitCap,
            onTimeout: () {},
          );
          continue;
        }
        if (!await iterator.moveNext()) break;
        final pieces = await decryptor.add(iterator.current);
        for (var piece in pieces) {
          if (skip > 0) {
            if (piece.length <= skip) {
              skip -= piece.length;
              continue;
            }
            piece = Uint8List.sublistView(piece, skip);
            skip = 0;
          }
          if (!firstPlainLogged) {
            firstPlainLogged = true;
            _diag(
              DiagCategory.playback,
              'proxy: producer at byte ${producer.anchor}: first '
              'plaintext, ${stopwatch.elapsedMilliseconds} ms after '
              'the producer started',
            );
          }
          produced += piece.length;
          _window.append(piece);
        }
      }
    } finally {
      await iterator.cancel();
    }
    _diag(
      DiagCategory.playback,
      'proxy: producer at byte ${producer.anchor} ended '
      '(${producer.cancelled ? 'cancelled' : 'upstream end'}), '
      '$produced plaintext bytes produced, '
      '${stopwatch.elapsedMilliseconds} ms elapsed',
    );
  }

  /// Parses a single-range `Range` header value against [total].
  /// Returns null when the header is absent, malformed or a
  /// multi-range (all served as a full 200), and the sentinel
  /// [unsatisfiableRange] when the start lies beyond the content.
  static const (int, int) unsatisfiableRange = (-1, -1);

  static (int, int)? _parseRange(String? header, int total) {
    if (header == null) return null;
    final value = header.trim();
    if (!value.startsWith('bytes=') || value.contains(',')) return null;
    final spec = value.substring(6).trim();
    final dash = spec.indexOf('-');
    if (dash < 0) return null;
    final startPart = spec.substring(0, dash).trim();
    final endPart = spec.substring(dash + 1).trim();
    if (startPart.isEmpty) {
      // Suffix range: the last N bytes.
      final suffix = int.tryParse(endPart);
      if (suffix == null || suffix <= 0) return null;
      return (suffix >= total ? 0 : total - suffix, total - 1);
    }
    final start = int.tryParse(startPart);
    if (start == null || start < 0) return null;
    if (start >= total) return unsatisfiableRange;
    var end = total - 1;
    if (endPart.isNotEmpty) {
      final parsedEnd = int.tryParse(endPart);
      if (parsedEnd == null || parsedEnd < start) return null;
      end = parsedEnd > total - 1 ? total - 1 : parsedEnd;
    }
    return (start, end);
  }

  Future<void> _handleSeekable(HttpRequest request) async {
    final total = _totalBytes!;
    final response = request.response;
    response.bufferOutput = false;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    final range = _parseRange(request.headers.value('range'), total);
    if (range == unsatisfiableRange) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set('Content-Range', 'bytes */$total');
      response.contentLength = 0;
      await response.close();
      return;
    }
    final ranged = range != null;
    final reqStart = ranged ? range.$1 : 0;
    var reqEnd = ranged ? range.$2 : total - 1;
    // A previously confirmed real end (plan 129) bounds this
    // request exactly like the declared total does: ranges
    // starting at or past it are unsatisfiable, and the
    // reported total becomes the real end.
    final eofByte = _eofByte;
    if (eofByte != null && reqStart >= eofByte) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set('Content-Range', 'bytes */$eofByte');
      response.contentLength = 0;
      await response.close();
      return;
    }
    if (eofByte != null && reqEnd >= eofByte) reqEnd = eofByte - 1;
    final reportedTotal = eofByte ?? total;
    response.headers.contentType = ContentType('video', 'mp2t');
    response.headers.set('Accept-Ranges', 'bytes');
    response.headers.set('transferMode.dlna.org', 'Streaming');
    if (request.method == 'HEAD') {
      response.statusCode = ranged ? HttpStatus.partialContent : HttpStatus.ok;
      if (ranged) {
        response.headers.set(
          'Content-Range',
          'bytes $reqStart-$reqEnd/$reportedTotal',
        );
      }
      response.contentLength = reqEnd - reqStart + 1;
      await response.close();
      return;
    }

    // A new GET supersedes the previous one (the player opens a
    // fresh connection per seek and abandons the old one).
    final generation = ++_serveGeneration;
    _window.currentGeneration = generation;
    _requestCount++;
    final requestNo = _requestCount;
    _diag(
      DiagCategory.playback,
      'proxy: request #$requestNo (seekable) '
      '${ranged ? 'range $reqStart-$reqEnd' : 'full stream'}',
    );

    // Decide where serving actually starts. Inside the window the
    // bytes are exact; outside it a producer must establish first
    // (its actual start can differ from the request only in the
    // last-resort case documented in _runProducer).
    var serveStart = reqStart;
    if (reqStart < _window.start || reqStart > _window.end) {
      _cancelProducer();
      final producer = _startProducer(reqStart);
      try {
        serveStart = await producer.established.future.timeout(
          seekEstablishTimeout,
        );
      } catch (e) {
        _diag(
          DiagCategory.playback,
          'proxy: request #$requestNo: the seek to byte $reqStart '
          'failed before serving: $e',
        );
        response.statusCode = HttpStatus.badGateway;
        try {
          await response.close();
        } catch (_) {}
        return;
      }
      if (generation != _serveGeneration) {
        // Superseded while establishing; the newer request owns
        // the producer now.
        try {
          await response.close();
        } catch (_) {}
        return;
      }
      if (serveStart > reqEnd) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set('Content-Range', 'bytes */$reportedTotal');
        response.contentLength = 0;
        await response.close();
        return;
      }
    } else if (_producer == null &&
        reqStart == _window.end &&
        _eofByte == null) {
      // The window is complete up to here but nothing is
      // producing the rest (an earlier stream ended early).
      _startProducer(reqStart);
    }

    response.statusCode = ranged ? HttpStatus.partialContent : HttpStatus.ok;
    if (ranged) {
      response.headers.set(
        'Content-Range',
        'bytes $serveStart-$reqEnd/$reportedTotal',
      );
    }
    response.contentLength = reqEnd - serveStart + 1;
    var pos = serveStart;
    var servedHere = 0;
    var stalledRestarts = 0;
    var consecutiveReconnectErrors = 0;
    var lastEnd = _window.end;
    var retriedProducerError = false;
    var completed = false;
    try {
      await response.flush();
      while (pos <= reqEnd) {
        if (generation != _serveGeneration || _stopRequested) {
          _diag(
            DiagCategory.playback,
            'proxy: request #$requestNo superseded at byte $pos',
          );
          break;
        }
        _window.setPin(pos, generation);
        final chunk = _window.readChunk(pos, 1024 * 1024);
        if (chunk != null) {
          consecutiveReconnectErrors = 0;
          final take = min(chunk.length, reqEnd - pos + 1);
          response.add(
            take == chunk.length
                ? chunk
                : Uint8List.sublistView(chunk, 0, take),
          );
          pos += take;
          servedHere += take;
          await response.flush();
          continue;
        }
        // Nothing at pos yet.
        if (pos < _window.start) {
          // The window was re-anchored by a newer producer.
          _diag(
            DiagCategory.playback,
            'proxy: request #$requestNo lost its window at byte $pos',
          );
          break;
        }
        final producer = _producer;
        if (producer != null && !producer.finished) {
          await _window.waitChange();
          continue;
        }
        final error = producer?.error;
        if (error != null) {
          if (_autoReconnect && _isTransientReconnectError(error)) {
            // Resume at the reader's byte (plan 129): back off,
            // drop the pooled sockets, re-authenticate when the
            // failure points at the session, and re-establish
            // the producer at pos. The window re-anchors at pos,
            // so bytes past it are re-fetched rather than trusted
            // across a producer change; a resume that can only
            // start PAST pos ends the response instead of
            // serving bytes at wrong offsets. Establishment
            // failures retry on the same ladder while they stay
            // transient; a committed refusal ends the response,
            // surfacing the failure as the truncated stream a
            // mid-stream failure has always produced.
            var reconnected = false;
            Object? lastError = error;
            while (!_stopRequested && generation == _serveGeneration) {
              final delay = _backoffForAttempt(consecutiveReconnectErrors);
              consecutiveReconnectErrors++;
              _diag(
                DiagCategory.playback,
                'proxy: request #$requestNo: reconnecting at byte '
                '$pos after ${delay.inMilliseconds} ms (attempt '
                '$consecutiveReconnectErrors, err=$lastError)',
              );
              if (delay > Duration.zero) {
                await Future<void>.delayed(delay);
              }
              if (_stopRequested || generation != _serveGeneration) break;
              _fetcher.resetClient();
              if (_shouldReauthenticate(
                lastError,
                consecutiveReconnectErrors,
              )) {
                await _reauthenticateForReconnect('seekable');
              }
              if (_stopRequested || generation != _serveGeneration) break;
              _cancelProducer();
              final retry = _startProducer(pos);
              try {
                final actual = await retry.established.future.timeout(
                  seekEstablishTimeout,
                );
                if (actual <= pos) {
                  reconnected = true;
                } else {
                  lastError = StateError(
                    'the resumed producer starts past byte $pos '
                    '(at $actual)',
                  );
                }
                break;
              } catch (e) {
                lastError = e;
                if (!_isTransientReconnectError(e)) break;
              }
            }
            if (reconnected) continue;
            _diag(
              DiagCategory.playback,
              'proxy: request #$requestNo: the resume at byte $pos '
              'did not re-establish: $lastError',
            );
            break;
          }
          // One fresh attempt when nothing has been served yet
          // (e.g. the primer failed before the player connected);
          // a failure mid-stream just ends the response.
          if (servedHere == 0 && !retriedProducerError) {
            retriedProducerError = true;
            _diag(
              DiagCategory.playback,
              'proxy: request #$requestNo: retrying after the '
              'producer failed at byte $pos: $error',
            );
            _cancelProducer();
            final retry = _startProducer(pos);
            int actual;
            try {
              actual = await retry.established.future.timeout(
                seekEstablishTimeout,
              );
            } catch (e) {
              _diag(
                DiagCategory.playback,
                'proxy: request #$requestNo: the retry failed: $e',
              );
              break;
            }
            if (actual != pos) break;
            continue;
          }
          _diag(
            DiagCategory.playback,
            'proxy: request #$requestNo: the producer failed at '
            'byte $pos: $error',
          );
          break;
        }
        if (_window.end >= total || pos >= total) break;
        if (_eofByte != null && _window.end >= _eofByte!) break;
        // The producer ended before the content did (a truncated
        // upstream stream): continue from the window end. Guard
        // against a source that keeps ending at the same byte.
        if (_window.end == lastEnd) {
          stalledRestarts++;
          if (_autoReconnect) {
            // A clean end short of the declared total, close to
            // it, is the content's real end (plan 129): the
            // declared size can overstate the actual stream, and
            // re-asking at the same byte only reproduces the
            // same end. Record it so later requests are bounded
            // by it too.
            final remaining = total - _window.end;
            if (remaining <= eofSlackBytes || remaining * 50 <= total) {
              _eofByte = _window.end;
              _diag(
                DiagCategory.playback,
                'proxy: request #$requestNo: the upstream ended '
                'at byte ${_window.end} of $total; treating it '
                'as the end of the content',
              );
              break;
            }
          }
          if (stalledRestarts >= 3) {
            _diag(
              DiagCategory.playback,
              'proxy: request #$requestNo: the upstream keeps '
              'ending at byte ${_window.end}; giving up',
            );
            break;
          }
          if (_autoReconnect) {
            // A clean end far from the declared total is a drop
            // that presented as an end: back off and resume
            // from the window end like any other drop
            // (plan 129).
            final delay = _backoffForAttempt(stalledRestarts - 1);
            _diag(
              DiagCategory.playback,
              'proxy: request #$requestNo: the upstream ended '
              'early at byte ${_window.end}; resuming after '
              '${delay.inMilliseconds} ms',
            );
            if (delay > Duration.zero) {
              await Future<void>.delayed(delay);
            }
            if (_stopRequested || generation != _serveGeneration) break;
            _fetcher.resetClient();
          }
        } else {
          stalledRestarts = 0;
          lastEnd = _window.end;
        }
        _startProducer(_window.end);
      }
      if (pos > reqEnd || (_eofByte != null && pos >= _eofByte!)) {
        completed = true;
        await response.close();
        _diag(
          DiagCategory.playback,
          'proxy: request #$requestNo completed, $servedHere bytes '
          'served from byte $serveStart',
        );
      }
    } catch (e) {
      _diag(
        DiagCategory.playback,
        'proxy: request #$requestNo ended with an error after '
        '$servedHere bytes: $e',
      );
    } finally {
      _window.releasePin(generation);
      if (!completed) {
        try {
          await response.close();
        } catch (_) {}
      }
    }
  }
}

/// One seekable-mode producer pipeline (plan 61): establishes its
/// plaintext start (see [DtcpProxy._runProducer]) and decrypts
/// into the window until the upstream ends or it is cancelled.
class _Producer {
  _Producer(this.anchor);

  /// The plaintext offset this producer was asked to start at.
  final int anchor;

  bool cancelled = false;
  bool finished = false;

  /// The producer's failure, when it ended with one.
  Object? error;

  /// Completes with the offset serving actually starts from
  /// (normally [anchor]; the source's start byte in the last
  /// resort), or with the establishment error.
  final Completer<int> established = Completer<int>();

  StreamIterator<List<int>>? iterator;
  Future<void>? runFuture;

  void finishEstablish(int actualStart) {
    if (!established.isCompleted) established.complete(actualStart);
  }

  void failEstablish(Object e) {
    if (!established.isCompleted) established.completeError(e);
  }
}

/// The source's time<->byte map (plan 61), learned point by point
/// from TimeSeekRange responses and interpolated piecewise
/// linearly. Seeded with (0, 0) and (duration, totalBytes): the
/// linear estimate, which measurement showed within a few seconds
/// for DR and a few tens of seconds for the mobile (VBR) encodes;
/// every real seek response refines the region it touched.
class _SeekMap {
  _SeekMap({required int totalBytes, required double totalSeconds})
    : _points = [(0.0, 0), (totalSeconds, totalBytes)];

  /// (seconds, byte) pairs, sorted by seconds; bytes grow
  /// monotonically with seconds.
  final List<(double, int)> _points;

  void learn(double seconds, int byte) {
    if (seconds <= 0) return;
    for (var i = 0; i < _points.length; i++) {
      final (t, _) = _points[i];
      if ((t - seconds).abs() < 0.001) {
        _points[i] = (seconds, byte);
        return;
      }
      if (t > seconds) {
        _points.insert(i, (seconds, byte));
        return;
      }
    }
    _points.add((seconds, byte));
  }

  /// The estimated time at which plaintext byte [byte] sits.
  double timeForByte(int byte) {
    if (byte <= 0) return 0;
    for (var i = 1; i < _points.length; i++) {
      final (t1, b1) = _points[i];
      if (byte <= b1) {
        final (t0, b0) = _points[i - 1];
        if (b1 == b0) return t1;
        return t0 + (t1 - t0) * (byte - b0) / (b1 - b0);
      }
    }
    return _points.last.$1;
  }
}

/// A contiguous window of decrypted plaintext with absolute
/// offsets (plan 61). One producer appends at the end; one reader
/// consumes through [readChunk]. Bytes below the reader's pin are
/// evicted once the window exceeds [DtcpProxy.windowCapBytes], so
/// short backward seeks are served from memory while memory stays
/// bounded. Waiters share one change signal and re-check their
/// own condition, as in [_PlaintextQueue].
class _WindowCache {
  _WindowCache({this._capBytes = DtcpProxy.windowCapBytes});

  /// The window bound in force (the production value is
  /// [DtcpProxy.windowCapBytes]; tests override it so the
  /// pause/pin behaviour is reachable with small fixtures).
  final int _capBytes;

  /// The window bound in force (see [_capBytes]).
  int get capBytes => _capBytes;

  final List<Uint8List> _chunks = [];
  int _start = 0;
  int _end = 0;
  bool _closed = false;
  Completer<void>? _changed;

  int? _pin;
  int _pinGeneration = -1;

  /// The serve generation currently allowed to pin the window,
  /// kept in step with the proxy's serve counter (plan 80). A
  /// pin left behind by an older generation belongs to a reader
  /// that has been superseded — possibly one stuck in a socket
  /// write it will never finish — and must not pace the
  /// producer: honouring it after a far re-anchor is what
  /// deadlocked the producer in plan 78.2.
  int currentGeneration = 0;

  /// Sets the reader pin for [generation] and wakes the
  /// waiters. The notification is load-bearing: a pin change
  /// can unpause the producer, and a producer already waiting
  /// when the serving handler first pins its position was the
  /// other half of the plan-78.2 deadlock.
  void setPin(int? pos, int generation) {
    _pin = pos;
    _pinGeneration = generation;
    _notify();
  }

  /// Releases the pin if [generation] still owns it.
  void releasePin(int generation) {
    if (_pinGeneration != generation) return;
    _pin = null;
    _pinGeneration = -1;
    _notify();
  }

  /// The pin the producer pacing and eviction must honour:
  /// the current generation's, or none.
  int? get effectivePin =>
      (_pin != null && _pinGeneration == currentGeneration) ? _pin : null;

  int get start => _start;
  int get end => _end;
  bool get isClosed => _closed;

  /// Whether the producer should pause: the window already holds
  /// a full cap of not-yet-consumed plaintext.
  bool get producerShouldPause => _end - (effectivePin ?? _start) >= _capBytes;

  /// Re-anchors the window at [offset] (a producer starts there):
  /// bytes from [offset] onward are dropped; a start outside the
  /// current window discards everything. The reader pin is
  /// invalidated: it referred to the pre-anchor layout, and the
  /// serving handler pins its own position when it starts
  /// consuming (plan 80).
  void anchor(int offset) {
    _pin = null;
    _pinGeneration = -1;
    if (offset < _start || offset > _end) {
      _chunks.clear();
      _start = offset;
      _end = offset;
    } else if (offset < _end) {
      var pos = _start;
      final kept = <Uint8List>[];
      for (final chunk in _chunks) {
        if (pos + chunk.length <= offset) {
          kept.add(chunk);
          pos += chunk.length;
        } else if (pos < offset) {
          kept.add(Uint8List.sublistView(chunk, 0, offset - pos));
          pos = offset;
          break;
        } else {
          break;
        }
      }
      _chunks
        ..clear()
        ..addAll(kept);
      _end = offset;
    }
    _notify();
  }

  void append(Uint8List chunk) {
    if (_closed || chunk.isEmpty) return;
    _chunks.add(chunk);
    _end += chunk.length;
    _evict();
    _notify();
  }

  void _evict() {
    final limit = effectivePin ?? _start;
    while (_end - _start > _capBytes && _start < limit) {
      final first = _chunks.first;
      final excess = _end - _start - _capBytes;
      final droppable = min(first.length, min(excess, limit - _start));
      if (droppable >= first.length) {
        _chunks.removeAt(0);
        _start += first.length;
      } else {
        _chunks[0] = Uint8List.sublistView(first, droppable);
        _start += droppable;
      }
    }
  }

  /// Up to [maxLength] bytes starting exactly at [offset] (a view
  /// into the retained chunk; retained plaintext is never mutated),
  /// or null when [offset] is outside the window.
  Uint8List? readChunk(int offset, int maxLength) {
    if (offset < _start || offset >= _end) return null;
    var pos = _start;
    for (final chunk in _chunks) {
      if (offset < pos + chunk.length) {
        final from = offset - pos;
        final take = min(chunk.length - from, maxLength);
        // Consumption can unpause the producer; wake the waiters.
        _notify();
        return Uint8List.sublistView(chunk, from, from + take);
      }
      pos += chunk.length;
    }
    return null;
  }

  void close() {
    _closed = true;
    _notify();
  }

  Future<void> waitChange() {
    if (_closed) return Future<void>.value();
    final completer = _changed ??= Completer<void>();
    return completer.future;
  }

  void notify() => _notify();

  void _notify() {
    final completer = _changed;
    _changed = null;
    completer?.complete();
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
