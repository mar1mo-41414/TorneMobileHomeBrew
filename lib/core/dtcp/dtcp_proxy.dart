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
class DtcpProxy {
  DtcpProxy._(this._server, this.uri);

  final HttpServer _server;

  /// The URL to hand to the player.
  final Uri uri;

  /// How long the content stream may go without a single byte
  /// before the proxy gives up (plan 29). The reference client
  /// applies its 30 s timeout as the socket read timeout; an
  /// unbounded wait here left the player spinning forever.
  static const Duration stallTimeout = Duration(seconds: 30);

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
    );
    var requestCount = 0;
    server.listen((request) async {
      if (request.uri.path != '/stream') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      requestCount++;
      final requestNo = requestCount;
      try {
        diag(
          DiagCategory.playback,
          'proxy: request #$requestNo from the player, content GET started',
        );
        final stopwatch = Stopwatch()..start();
        final response = await fetcher.openContent(contentUrl);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.headers.set('transferMode.dlna.org', 'Streaming');
        final decryptor = PcpDecryptor(keyForLabel: keyForLabel);
        var packetCount = 0;
        var plainBytes = 0;
        var cipherBytes = 0;
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
        await for (final chunk in timed) {
          cipherBytes += chunk.length;
          final plainChunks = await decryptor.add(chunk);
          for (final plain in plainChunks) {
            packetCount++;
            plainBytes += plain.length;
            if (packetCount == 1) {
              diag(
                DiagCategory.playback,
                'proxy: first packet decrypted, ${plain.length} bytes '
                'plaintext, ${stopwatch.elapsedMilliseconds} ms after '
                'the content GET',
              );
            } else if (packetCount % 50 == 0) {
              diag(
                DiagCategory.playback,
                'proxy: $packetCount packets, $plainBytes bytes '
                'decrypted so far',
              );
            }
            // Await the flush per packet: the player paces the
            // upstream reads, and buffered plaintext stays bounded
            // to about one packet (plan 29).
            request.response.add(plain);
            await request.response.flush();
          }
        }
        await request.response.close();
        diag(
          DiagCategory.playback,
          'proxy: stream ended, $packetCount packets, $plainBytes '
          'bytes decrypted ($cipherBytes bytes received)',
        );
      } catch (e) {
        diag(DiagCategory.playback, 'proxy: stream error: $e');
        // Playback errors surface to the player as a closed stream;
        // the session owner reports them through its own channel.
        try {
          request.response.statusCode = HttpStatus.badGateway;
          await request.response.close();
        } catch (_) {}
      }
    });
    return proxy;
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }
}
