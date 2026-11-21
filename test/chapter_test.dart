/// Chapter data source tests (plan 112): the
/// X_GetTitleInfo document shape, the validation that
/// keeps the unit's broken chapter data out, and the
/// service boundary that turns every failure into
/// "no chapters".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';

/// The Sakana title's X_GetTitleInfo response, as
/// measured on the real unit (plan 110): the Result
/// document's root carries the fields directly.
const sakanaResult =
    '<?xml version="1.0"?>'
    '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/">'
    '<chapterNum>5</chapterNum>'
    '<chapterTime>0_175_16265924_32657800_38986622</chapterTime>'
    '<startPTS>3691981196</startPTS>'
    '</xsrs>';

/// Metadata plays no part in fetchChapters; an empty
/// stub keeps the service construction honest.
class _NoMetadata implements MetadataService {
  const _NoMetadata();

  @override
  Future<DidlDocument> browse(String objectId) async =>
      const DidlDocument(containers: [], items: []);

  @override
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  ) async => EpgGuide(broadcastingType: broadcastingType, services: const []);

  @override
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType) async =>
      const {};
}

String soapEnvelope(String result) {
  final escaped = result
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return '<?xml version="1.0"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body>'
      '<u:X_GetTitleInfoResponse xmlns:u="urn:schemas-s-bras-org:service:X_PvrControl:1">'
      '<Result>$escaped</Result>'
      '</u:X_GetTitleInfoResponse>'
      '</s:Body></s:Envelope>';
}

void main() {
  group('parseTitleInfoDocument', () {
    test('reads the fields off the xsrs root', () {
      final fields = parseTitleInfoDocument(
        sakanaResult,
        'soap:X_GetTitleInfo',
      );
      expect(fields.chapterNum, '5');
      expect(fields.chapterTime, '0_175_16265924_32657800_38986622');
      expect(fields.startPTS, '3691981196');
    });

    test('a document without the fields parses to nulls', () {
      final fields = parseTitleInfoDocument(
        '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/"></xsrs>',
        'soap:X_GetTitleInfo',
      );
      expect(fields.chapterNum, isNull);
      expect(fields.chapterTime, isNull);
      expect(fields.startPTS, isNull);
    });

    test('a non-xsrs root is a parse error', () {
      expect(
        () => parseTitleInfoDocument('<didl/>', 'soap:X_GetTitleInfo'),
        throwsA(isA<NasneError>()),
      );
    });

    test('malformed XML is a parse error', () {
      expect(
        () => parseTitleInfoDocument('<xsrs', 'soap:X_GetTitleInfo'),
        throwsA(isA<NasneError>()),
      );
    });
  });

  group('chapterPositionsFromTitleInfo', () {
    List<Duration> positions(
      String chapterNum,
      String chapterTime,
      String startPTS, {
      int durationSeconds = 1048,
    }) {
      return chapterPositionsFromTitleInfo(
        TitleInfoFields(
          chapterNum: chapterNum,
          chapterTime: chapterTime,
          startPTS: startPTS,
        ),
        durationSeconds: durationSeconds,
      );
    }

    test('the Sakana title converts to its measured cuts', () {
      // Plan 110: 0 / 0.004 / 361.465 / 725.729 /
      // 866.369 s, with the 0.004 s point thinned as a
      // near-duplicate of the start point.
      final result = positions(
        '5',
        '0_175_16265924_32657800_38986622',
        '3691981196',
      );
      expect(result.map((d) => d.inMilliseconds), [0, 361464, 725728, 866369]);
    });

    test('the broken PR-spot data is rejected', () {
      // Plan 110: the short PR spots carry the sentinel
      // startPTS and a garbage second token.
      final result = positions(
        '2',
        '0_15296768848949906338',
        '3149975228739148456',
        durationSeconds: 54,
      );
      expect(result, isEmpty);
    });

    test('a sentinel startPTS alone rejects the title', () {
      final result = positions(
        '3',
        '0_657657_4256753',
        '3149975228739148456',
        durationSeconds: 298,
      );
      expect(result, isEmpty);
    });

    test('a token count other than chapterNum is rejected', () {
      expect(positions('4', '0_45000_90000', '123456789'), isEmpty);
      expect(positions('2', '0_45000_90000', '123456789'), isEmpty);
    });

    test('a decreasing token is rejected', () {
      expect(
        positions('3', '0_500000_400000', '123456789', durationSeconds: 100),
        isEmpty,
      );
    });

    test('a non-numeric or negative token is rejected', () {
      expect(positions('2', '0_abc', '123456789'), isEmpty);
      expect(positions('2', '0_-45000', '123456789'), isEmpty);
      expect(positions('2', '0_', '123456789'), isEmpty);
    });

    test('the last token must end within the recording', () {
      // Duration 1000 s: the bound is 1000 * 45000 *
      // 1.02 = 45,900,000 units.
      expect(
        positions('2', '0_45900000', '123456789', durationSeconds: 1000),
        hasLength(2),
      );
      expect(
        positions('2', '0_45900001', '123456789', durationSeconds: 1000),
        isEmpty,
      );
      expect(
        positions('2', '0_450000000', '123456789', durationSeconds: 1000),
        isEmpty,
      );
    });

    test('points closer than a second to the kept one thin out', () {
      // Exactly a second apart is kept; just under is
      // thinned.
      final result = positions(
        '4',
        '0_44999_45000_90000',
        '123456789',
        durationSeconds: 100,
      );
      expect(result, [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    });

    test('equal neighbour tokens are duplicates, not corruption', () {
      final result = positions(
        '4',
        '0_90000_90000_180000',
        '123456789',
        durationSeconds: 100,
      );
      expect(result, [
        Duration.zero,
        const Duration(seconds: 2),
        const Duration(seconds: 4),
      ]);
    });

    test('a list thinned below two points is no chapter list', () {
      expect(
        positions('2', '0_175', '123456789', durationSeconds: 100),
        isEmpty,
      );
    });

    test('missing or empty fields are no chapters', () {
      expect(
        chapterPositionsFromTitleInfo(
          const TitleInfoFields(),
          durationSeconds: 100,
        ),
        isEmpty,
      );
      expect(positions('0', '', '123456789'), isEmpty);
      expect(positions('', '0_45000', '123456789'), isEmpty);
      expect(positions('2', '0_45000', ''), isEmpty);
    });

    test('an unknown duration validates nothing', () {
      expect(
        positions('2', '0_45000', '123456789', durationSeconds: 0),
        isEmpty,
      );
    });
  });

  group('SoapTitleCatalogService.fetchChapters', () {
    SoapTitleCatalogService build(MockClient client, {Uri? pvrControlUrl}) {
      return SoapTitleCatalogService(
        soap: SoapTransport(client: client),
        xsrsControlUrl: Uri.parse('http://192.0.2.1:64230/XSRS'),
        webApi: WebApiTransport('192.0.2.1', client: client),
        metadata: const _NoMetadata(),
        pvrControlUrl: pvrControlUrl,
      );
    }

    final pvrUrl = Uri.parse('http://192.0.2.1:64230/X_PvrControl');

    test('fetches and validates through X_GetTitleInfo', () async {
      late String seenBody;
      late Uri seenUrl;
      final service = build(
        MockClient((request) async {
          seenUrl = request.url;
          seenBody = request.body;
          return http.Response(
            soapEnvelope(sakanaResult),
            200,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        }),
        pvrControlUrl: pvrUrl,
      );
      final chapters = await service.fetchChapters(
        '17952235570000000207',
        durationSeconds: 1048,
      );
      expect(chapters.map((d) => d.inMilliseconds), [
        0,
        361464,
        725728,
        866369,
      ]);
      expect(seenUrl, pvrUrl);
      expect(seenBody, contains('<TitleID>17952235570000000207</TitleID>'));
      expect(seenBody, contains('X_GetTitleInfo'));
    });

    test('a transport failure is no chapters, not an error', () async {
      final service = build(
        MockClient((request) async => http.Response('boom', 500)),
        pvrControlUrl: pvrUrl,
      );
      expect(await service.fetchChapters('1', durationSeconds: 100), isEmpty);
    });

    test('broken chapter data is no chapters, not an error', () async {
      final service = build(
        MockClient((request) async {
          return http.Response(
            soapEnvelope(
              '<?xml version="1.0"?>'
              '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/">'
              '<chapterNum>2</chapterNum>'
              '<chapterTime>0_15296768848949906338</chapterTime>'
              '<startPTS>3149975228739148456</startPTS>'
              '</xsrs>',
            ),
            200,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        }),
        pvrControlUrl: pvrUrl,
      );
      expect(await service.fetchChapters('1', durationSeconds: 54), isEmpty);
    });

    test('without a PvrControl URL there are no chapters', () async {
      final service = build(
        MockClient((request) async => http.Response('unused', 500)),
      );
      expect(await service.fetchChapters('1', durationSeconds: 100), isEmpty);
    });
  });
}
