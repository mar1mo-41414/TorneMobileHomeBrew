/// Progressive title listing (plan 100): the catalog emits the
/// accumulated titles after a small first chunk and after every
/// further page, and marks only the DIDL-merged emission
/// complete. The MockClient honours RequestedCount the way the
/// unit does (plan 74.10: an explicit count is served as asked;
/// 0 takes the server's own page).
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';

final xsrsUrl = Uri.parse('http://192.0.2.1:64230/XSRS');

void main() {
  group('SoapTitleCatalogService.listTitlesProgressively', () {
    SoapTitleCatalogService build(
      MockClient client, {
      MetadataService? metadata,
    }) {
      return SoapTitleCatalogService(
        soap: SoapTransport(client: client),
        xsrsControlUrl: xsrsUrl,
        webApi: WebApiTransport('192.0.2.1', client: client),
        metadata: metadata ?? _EmptyMetadata(),
      );
    }

    /// Serves X_GetTitleList out of [total] titles, honouring
    /// RequestedCount (0 = the server page of [serverPage]).
    /// Records (StartingIndex, RequestedCount) of every call.
    MockClient titleClient({
      required int total,
      int serverPage = 200,
      required List<(int, int)> requests,
    }) {
      return MockClient((request) async {
        int arg(String name) => int.parse(
          RegExp('<$name>(\\d+)</$name>').firstMatch(request.body)!.group(1)!,
        );
        final start = arg('StartingIndex');
        final count = arg('RequestedCount');
        requests.add((start, count));
        final serve = count == 0 ? serverPage : count;
        final end = min(start + serve, total);
        final ids = [for (var i = start + 1; i <= end; i++) i];
        return http.Response(
          _xsrsResponse(
            ids,
            numberReturned: ids.length,
            totalMatches: total,
          ),
          200,
          headers: {'content-type': 'text/xml; charset=utf-8'},
        );
      });
    }

    test('first chunk is small, pages follow, only the last '
        'stage is complete', () async {
      final requests = <(int, int)>[];
      final catalog = build(titleClient(total: 45, requests: requests));
      final stages = await catalog
          .listTitlesProgressively(withMetadata: false)
          .toList();
      // First request asks for the small chunk explicitly; the
      // next takes the server page from where the chunk ended.
      expect(requests, [(0, SoapTitleCatalogService.firstChunkSize), (20, 0)]);
      expect(stages.map((s) => s.titles.length), [20, 45, 45]);
      expect(stages.map((s) => s.complete), [false, false, true]);
      expect(stages.last.titles.first.id, '1');
      expect(stages.last.titles.last.id, '45');
    });

    test('a list within the first chunk takes one request', () async {
      final requests = <(int, int)>[];
      final catalog = build(titleClient(total: 5, requests: requests));
      final stages = await catalog
          .listTitlesProgressively(withMetadata: false)
          .toList();
      expect(requests, [(0, SoapTitleCatalogService.firstChunkSize)]);
      expect(stages.map((s) => s.titles.length), [5, 5]);
      expect(stages.map((s) => s.complete), [false, true]);
    });

    test('the DIDL complement lands only in the complete stage', () async {
      final requests = <(int, int)>[];
      final metadata = _FakeMetadata(
        const DidlDocument(
          containers: [],
          items: [
            DidlItem(
              id: '0/video/all/pvr?id=1',
              parentId: '0/video/all',
              title: '番組1',
              channelName: 'テスト放送',
              copyCountRemaining: 7,
              properties: {'upnp:genre': 'ニュース／報道'},
            ),
          ],
        ),
      );
      final catalog = build(
        titleClient(total: 25, requests: requests),
        metadata: metadata,
      );
      final stages = await catalog.listTitlesProgressively().toList();
      expect(metadata.browseCalls, 1);
      expect(stages.map((s) => s.titles.length), [20, 25, 25]);
      expect(stages.map((s) => s.complete), [false, false, true]);
      // Intermediate stages are XSRS-only: no channel name yet.
      expect(stages.first.titles.first.channelName, isNull);
      final merged = stages.last.titles.first;
      expect(merged.channelName, 'テスト放送');
      expect(merged.copyCountRemaining, 7);
      expect(merged.genre, 'ニュース／報道');
    });

    test('listTitles still returns the merged whole list', () async {
      final requests = <(int, int)>[];
      final catalog = build(titleClient(total: 45, requests: requests));
      final titles = await catalog.listTitles(withMetadata: false);
      expect(titles.length, 45);
      expect(titles.first.id, '1');
      expect(titles.last.id, '45');
    });
  });
}

class _FakeMetadata implements MetadataService {
  _FakeMetadata(this.doc);

  final DidlDocument doc;
  int browseCalls = 0;

  @override
  Future<DidlDocument> browse(String objectId) async {
    browseCalls++;
    return doc;
  }

  @override
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  ) async => EpgGuide(broadcastingType: broadcastingType, services: const []);

  @override
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType) async =>
      const {};
}

class _EmptyMetadata extends _FakeMetadata {
  _EmptyMetadata() : super(const DidlDocument(containers: [], items: []));
}

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _xsrsResponse(
  List<int> ids, {
  required int numberReturned,
  required int totalMatches,
}) {
  final items =
      ids.map((n) => '<item id="$n"><title>番組$n</title></item>').join();
  final result = '<?xml version="1.0"?>'
      '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/">$items</xsrs>';
  return '<?xml version="1.0"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body>'
      '<u:X_GetTitleListResponse xmlns:u="urn:schemas-xsrs-org:service:X_ScheduledRecording:2">'
      '<Result>${_escapeXml(result)}</Result>'
      '<NumberReturned>$numberReturned</NumberReturned>'
      '<TotalMatches>$totalMatches</TotalMatches>'
      '</u:X_GetTitleListResponse></s:Body></s:Envelope>';
}
