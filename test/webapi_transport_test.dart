/// WebApiTransport behaviour with a mock HTTP client.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('GET', () {
    test('decodes a JSON object and builds the measured URL', () async {
      late Uri seenUrl;
      final client = MockClient((request) async {
        seenUrl = request.url;
        return http.Response(
          jsonEncode({'errorcode': 0, 'name': 'nasne-test'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final transport = WebApiTransport('192.0.2.1', client: client);
      final json = await transport.getJson(WebApiEndpoints.boxNameGet);
      expect(json['name'], 'nasne-test');
      expect(seenUrl.toString(), 'http://192.0.2.1:64210/status/boxNameGet');
    });

    test('a non-zero errorcode becomes a webapi NasneError', () async {
      final client = MockClient((request) async =>
          http.Response(jsonEncode({'errorcode': 5}), 200));
      final transport = WebApiTransport('192.0.2.1', client: client);
      await expectLater(
        transport.getJson(WebApiEndpoints.boxNameGet),
        throwsA(isA<NasneError>()
            .having((e) => e.category, 'category', NasneErrorCategory.webapi)
            .having((e) => e.code, 'code', '5')),
      );
    });

    test('404 reads as not-implemented (measured for dead endpoints)',
        () async {
      final client = MockClient((request) async => http.Response('', 404));
      final transport = WebApiTransport('192.0.2.1', client: client);
      await expectLater(
        transport.getJson(WebApiEndpoints.boxNameGet),
        throwsA(isA<NasneError>()
            .having((e) => e.messageKey, 'key', 'error.notImplemented')),
      );
    });

    test('a missing required parameter fails client-side', () async {
      final transport = WebApiTransport('192.0.2.1', client: MockClient(
          (request) async => http.Response('{}', 200)));
      await expectLater(
        transport.getJson(WebApiEndpoints.channelListGet),
        throwsA(isA<NasneError>()
            .having((e) => e.category, 'category',
                NasneErrorCategory.validation)),
      );
    });
  });

  group('POST + token', () {
    test('PINVerify carries the known-value token for an empty body',
        () async {
      late Map<String, String> seenHeaders;
      late String seenBody;
      final client = MockClient((request) async {
        seenHeaders = request.headers;
        seenBody = request.body;
        return http.Response(jsonEncode({'errorcode': 0}), 200);
      });
      final transport = WebApiTransport(
        '192.0.2.1',
        client: client,
        tokenProvider: const TokenProvider('334455'),
      );
      await transport.postJson(WebApiEndpoints.pinVerify);
      expect(seenBody, '');
      expect(seenHeaders['X-DTVToken'], '9JOKWxjRn9ykWcZg64FM+gJC7Ik=');
      expect(seenHeaders['Content-Type'],
          contains('application/x-www-form-urlencoded'));
    });

    test('an auth endpoint without a TokenProvider fails client-side',
        () async {
      final transport = WebApiTransport('192.0.2.1',
          client: MockClient((request) async => http.Response('{}', 200)));
      await expectLater(
        transport.postJson(WebApiEndpoints.pinVerify),
        throwsA(isA<NasneError>()
            .having((e) => e.category, 'category',
                NasneErrorCategory.validation)),
      );
    });

    test('HTTP 400 on a POST is a webapi rejection (token control, 11.5)',
        () async {
      final client = MockClient((request) async => http.Response('', 400));
      final transport = WebApiTransport(
        '192.0.2.1',
        client: client,
        tokenProvider: const TokenProvider('334455'),
      );
      await expectLater(
        transport.postJson(WebApiEndpoints.boxNameSet,
            form: {'name': 'x'}),
        throwsA(isA<NasneError>()
            .having((e) => e.category, 'category', NasneErrorCategory.webapi)
            .having((e) => e.code, 'code', '400')),
      );
    });
  });
}
