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

import '../errors.dart';
import 'ake.dart';
import 'pcp.dart';

/// Supplies the media response: HEAD/GET against the content URL
/// with the DLNA/DTCP headers the source expects (pydtcpip client).
class DtcpMediaFetcher {
  DtcpMediaFetcher({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  HttpClient? _client;

  HttpClient get _http => _client ??= _clientFactory();

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  /// Issues the HEAD request that reveals the AKE endpoint
  /// (DTCP1HOST / DTCP1PORT content features).
  Future<(String host, int port)> akeEndpoint(Uri contentUrl) async {
    final request = await _http.headUrl(contentUrl);
    _applyHeaders(request);
    final response = await request.close();
    final contentType = response.headers.contentType;
    await response.drain<void>();
    final host = contentType?.parameters['DTCP1HOST'];
    final port = int.tryParse(contentType?.parameters['DTCP1PORT'] ?? '');
    if (host == null || port == null) {
      throw NasneError.parse(
        'dtcp:http',
        cause: 'the content response carries no DTCP endpoint',
      );
    }
    return (host, port);
  }

  /// Opens the GET response for the same URL (must be the same
  /// endpoint the HEAD was issued against).
  Future<HttpClientResponse> openContent(Uri contentUrl) async {
    final request = await _http.getUrl(contentUrl);
    _applyHeaders(request);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw NasneError.http(response.statusCode, 'dtcp:http');
    }
    return response;
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

  static Future<DtcpProxy> start({
    required Uri contentUrl,
    required AkeSession session,
    required DtcpMediaFetcher fetcher,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = DtcpProxy._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/stream'),
    );
    server.listen((request) async {
      if (request.uri.path != '/stream') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      try {
        final response = await fetcher.openContent(contentUrl);
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.headers.set('transferMode.dlna.org', 'Streaming');
        final decryptor = PcpDecryptor(
          keyForLabel: (label) => session.waitExchangeKey(
            label,
            timeout: const Duration(seconds: 15),
          ),
        );
        await for (final chunk in response) {
          final plainChunks = await decryptor.add(chunk);
          for (final plain in plainChunks) {
            request.response.add(plain);
          }
        }
        await request.response.close();
      } catch (_) {
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
