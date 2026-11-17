/// Media fetcher HEAD tests (plan 28 regression).
///
/// Kept apart from dtcp_test.dart on purpose: that file uses
/// testWidgets, whose binding replaces HttpClient with a mock
/// that answers 400 to everything. These tests exercise the real
/// dart:io client against a local server.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('media fetcher HEAD (plan 28 regression)', () {
    // Build 6 failed every playback start here: dart:io lowercases
    // Content-Type parameter names, so parameters['DTCP1HOST']
    // never matched. The fetcher now parses the raw header.
    Future<(HttpServer, Uri)> serve(
      void Function(HttpRequest request) respond,
    ) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        respond(request);
        await request.response.close();
      });
      return (server, Uri.parse('http://127.0.0.1:${server.port}/content'));
    }

    test('the measured nasne HEAD response yields the endpoint', () async {
      final (server, url) = await serve((request) {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-dtcp1; DTCP1HOST=192.168.11.129; '
          'DTCP1PORT=58293; CONTENTFORMAT="video/vnd.dlna.mpeg-tts"',
        );
      });
      final fetcher = DtcpMediaFetcher();
      final (host, port) = await fetcher.akeEndpoint(url);
      expect(host, '192.168.11.129');
      expect(port, 58293);
      fetcher.close();
      await server.close(force: true);
    });

    test('a non-200 HEAD is an http error, not a missing endpoint',
        () async {
      final (server, url) = await serve((request) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-dtcp1; DTCP1HOST=192.168.11.129; DTCP1PORT=58293',
        );
      });
      final fetcher = DtcpMediaFetcher();
      await expectLater(
        fetcher.akeEndpoint(url),
        throwsA(
          isA<NasneError>().having(
            (e) => e.category,
            'category',
            NasneErrorCategory.http,
          ),
        ),
      );
      fetcher.close();
      await server.close(force: true);
    });

    test('a non-DTCP media type is a parse error', () async {
      final (server, url) = await serve((request) {
        request.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'text/html; charset=utf-8',
        );
      });
      final fetcher = DtcpMediaFetcher();
      await expectLater(
        fetcher.akeEndpoint(url),
        throwsA(
          isA<NasneError>().having(
            (e) => e.category,
            'category',
            NasneErrorCategory.parse,
          ),
        ),
      );
      fetcher.close();
      await server.close(force: true);
    });
  });
}
