/// Paged list fetching (plan 74.10): fetchAllListPages mechanics
/// plus the two services that page — X_GetTitleList and Browse —
/// against MockClient handlers keyed by StartingIndex.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';

final xsrsUrl = Uri.parse('http://192.0.2.1:64230/XSRS');
final cdsUrl = Uri.parse(
  'http://192.0.2.1:58888/MediaServer_ContentDirectory/control',
);

SoapResponse _page(List<String> entries, int? numberReturned,
        int? totalMatches) =>
    SoapResponse({
      'Result': entries.join(','),
      if (numberReturned != null) 'NumberReturned': '$numberReturned',
      if (totalMatches != null) 'TotalMatches': '$totalMatches',
    });

/// Runs fetchAllListPages over a scripted page sequence, returning
/// the accumulated entries and the StartingIndex of every request.
Future<(List<String>, List<int>)> _run(List<SoapResponse> pages) async {
  final requested = <int>[];
  final accumulated = <String>[];
  var next = 0;
  await fetchAllListPages(
    requestPage: (startingIndex) async {
      requested.add(startingIndex);
      return pages[next++];
    },
    consumePage: (resp) {
      final result = resp.result!;
      if (result.isEmpty) return 0;
      final entries = result.split(',');
      accumulated.addAll(entries);
      return entries.length;
    },
  );
  return (accumulated, requested);
}

void main() {
  group('fetchAllListPages', () {
    test('concatenates pages in order until TotalMatches', () async {
      final (accumulated, requested) = await _run([
        _page(['1', '2'], 2, 5),
        _page(['3', '4'], 2, 5),
        _page(['5'], 1, 5),
      ]);
      expect(requested, [0, 2, 4]);
      expect(accumulated, ['1', '2', '3', '4', '5']);
    });

    test('203 entries behind the 200-entry default page', () async {
      final (accumulated, requested) = await _run([
        _page([for (var i = 1; i <= 200; i++) '$i'], 200, 203),
        _page(['201', '202', '203'], 3, 203),
      ]);
      expect(requested, [0, 200]);
      expect(accumulated.length, 203);
      expect(accumulated.toSet().length, 203);
      expect(accumulated.first, '1');
      expect(accumulated.last, '203');
    });

    test('stops when a page reports NumberReturned 0', () async {
      final (accumulated, requested) = await _run([
        _page(['1', '2'], 2, 10),
        _page([], 0, 10),
      ]);
      expect(requested, [0, 2]);
      expect(accumulated, ['1', '2']);
    });

    test('stops at the page cap when pages never end', () async {
      var requests = 0;
      final accumulated = <String>[];
      await fetchAllListPages(
        requestPage: (startingIndex) async {
          requests++;
          return _page(['$startingIndex'], 1, 1000000);
        },
        consumePage: (resp) {
          accumulated.add(resp.result!);
          return 1;
        },
      );
      expect(requests, maxListPages);
      expect(accumulated.length, maxListPages);
    });

    test('a list that fits in one page takes exactly one request',
        () async {
      final (accumulated, requested) = await _run([
        _page(['1', '2'], 2, 2),
      ]);
      expect(requested, [0]);
      expect(accumulated, ['1', '2']);
    });

    test('absent counts mean the first page is the whole list',
        () async {
      final (accumulated, requested) = await _run([
        _page(['1', '2'], null, null),
      ]);
      expect(requested, [0]);
      expect(accumulated, ['1', '2']);
    });
  });

  group('SoapTitleCatalogService paging', () {
    SoapTitleCatalogService build(MockClient client) {
      return SoapTitleCatalogService(
        soap: SoapTransport(client: client),
        xsrsControlUrl: xsrsUrl,
        webApi: WebApiTransport('192.0.2.1', client: client),
        metadata: _UnusedMetadata(),
      );
    }

    /// Serves X_GetTitleList in pages of [pageSize] out of [total]
    /// titles, like the device's default page (plan 74.10).
    MockClient titleClient({
      required int total,
      required int pageSize,
      required List<int> requestedIndices,
    }) {
      return MockClient((request) async {
        final match = RegExp(r'<StartingIndex>(\d+)</StartingIndex>')
            .firstMatch(request.body)!;
        final start = int.parse(match.group(1)!);
        requestedIndices.add(start);
        final end = min(start + pageSize, total);
        final ids = [for (var i = start + 1; i <= end; i++) i];
        return http.Response(
          _xsrsResponse(ids,
              numberReturned: ids.length, totalMatches: total),
          200,
          headers: {'content-type': 'text/xml; charset=utf-8'},
        );
      });
    }

    test('203 titles are fetched past the 200-entry default page',
        () async {
      final requested = <int>[];
      final catalog = build(
        titleClient(total: 203, pageSize: 200, requestedIndices: requested),
      );
      final titles = await catalog.listTitles(withMetadata: false);
      expect(requested, [0, 200]);
      expect(titles.length, 203);
      expect(titles.map((t) => t.id).toSet().length, 203);
      expect(titles.first.id, '1');
      expect(titles.last.id, '203');
    });

    test('a list within one page takes exactly one request', () async {
      final requested = <int>[];
      final catalog = build(
        titleClient(total: 2, pageSize: 200, requestedIndices: requested),
      );
      final titles = await catalog.listTitles(withMetadata: false);
      expect(requested, [0]);
      expect(titles.length, 2);
    });
  });

  group('DlnaMetadataService paging', () {
    test('pages are merged in order, containers counted', () async {
      final requested = <int>[];
      final service = DlnaMetadataService(
        soap: SoapTransport(
          client: MockClient((request) async {
            final match = RegExp(r'<StartingIndex>(\d+)</StartingIndex>')
                .firstMatch(request.body)!;
            final start = int.parse(match.group(1)!);
            requested.add(start);
            // Page 1 carries a container and an item; the entry
            // count that ends paging must include both.
            final inner = switch (start) {
              0 =>
                '<container id="0/video/all/sub" parentID="0/video/all" childCount="0">'
                    '<dc:title>サブ</dc:title></container>'
                    '<item id="0/video/all/pvr?id=101" parentID="0/video/all">'
                    '<dc:title>番組101</dc:title></item>',
              2 =>
                '<item id="0/video/all/pvr?id=102" parentID="0/video/all">'
                    '<dc:title>番組102</dc:title></item>',
              _ => '',
            };
            final returned = start == 0 ? 2 : 1;
            return http.Response(
              _browseResponse(inner,
                  numberReturned: returned, totalMatches: 3),
              200,
              headers: {'content-type': 'text/xml; charset=utf-8'},
            );
          }),
        ),
        controlUrl: cdsUrl,
      );
      final doc = await service.browse('0/video/all');
      expect(requested, [0, 2]);
      expect(doc.containers.single.id, '0/video/all/sub');
      expect(
        doc.items.map((i) => i.titleId),
        ['101', '102'],
      );
    });

    test('a Browse within one page takes exactly one request', () async {
      var requests = 0;
      final service = DlnaMetadataService(
        soap: SoapTransport(
          client: MockClient((request) async {
            requests++;
            return http.Response(
              _browseResponse(
                '<item id="0/video/all/pvr?id=101" parentID="0/video/all">'
                '<dc:title>番組101</dc:title></item>',
                numberReturned: 1,
                totalMatches: 1,
              ),
              200,
              headers: {'content-type': 'text/xml; charset=utf-8'},
            );
          }),
        ),
        controlUrl: cdsUrl,
      );
      final doc = await service.browse('0/video/all');
      expect(requests, 1);
      expect(doc.items.single.titleId, '101');
    });
  });
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

String _browseResponse(
  String didlInner, {
  required int numberReturned,
  required int totalMatches,
}) {
  final result = '<DIDL-Lite '
      'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '$didlInner</DIDL-Lite>';
  return '<?xml version="1.0"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body>'
      '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
      '<Result>${_escapeXml(result)}</Result>'
      '<NumberReturned>$numberReturned</NumberReturned>'
      '<TotalMatches>$totalMatches</TotalMatches>'
      '<UpdateID>0</UpdateID>'
      '</u:BrowseResponse></s:Body></s:Envelope>';
}

class _UnusedMetadata implements MetadataService {
  @override
  Future<DidlDocument> browse(String objectId) async =>
      const DidlDocument(containers: [], items: []);

  @override
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  ) async =>
      EpgGuide(broadcastingType: broadcastingType, services: const []);

  @override
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType) async =>
      const {};
}
