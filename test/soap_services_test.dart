/// SOAP services against MockClient + masked phase 0 fixtures.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';

String soapFixture(String name) =>
    File('test/fixtures/soap/$name').readAsStringSync();

final xsrsUrl = Uri.parse('http://192.0.2.1:64230/XSRS');
final cdsUrl = Uri.parse(
  'http://192.0.2.1:58888/MediaServer_ContentDirectory/control',
);

/// Routes by the SOAP action name found in the request body.
MockClient router(
  Map<String, (int, String)> routes, {
  void Function(http.Request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    for (final entry in routes.entries) {
      if (request.body.contains('<u:${entry.key} ') ||
          request.body.contains('<u:${entry.key}>')) {
        return http.Response(
          entry.value.$2,
          entry.value.$1,
          headers: {'content-type': 'text/xml; charset=utf-8'},
        );
      }
    }
    return http.Response('no route', 500);
  });
}

void main() {
  group('SoapScheduleService', () {
    test('list parses the one-item fixture', () async {
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: router({
            'X_GetRecordScheduleList': (
              200,
              soapFixture('schedule_list_one.xml'),
            ),
          }),
        ),
        controlUrl: xsrsUrl,
      );
      final list = await service.listSchedules();
      expect(list.length, 1);
      expect(list.single.id, '10000000000000000004');
    });

    test('create returns the normalised id (0x stripped)', () async {
      late String seenBody;
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: router({
            'X_CreateRecordSchedule': (200, soapFixture('create_response.xml')),
          }, onRequest: (r) => seenBody = r.body),
        ),
        controlUrl: xsrsUrl,
      );
      final id = await service.createSchedule(
        NewRecordSchedule(
          start: DateTime.parse('2026-11-18T04:00:00+09:00'),
          durationSeconds: 300,
          channel: const ScheduleChannel(
            broadcastingType: 2,
            channelType: 2,
            serviceId: 56832,
          ),
          networkId: 30848,
        ),
      );
      expect(id, '10000000000000000003');
      // The Elements argument is transported XML-escaped (plan 12.3).
      expect(seenBody, contains('&lt;scheduledStartDateTime&gt;'));
      expect(seenBody, contains('X_CreateRecordSchedule'));
    });

    test('delete sends the canonical id', () async {
      late String seenBody;
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: router({
            'X_DeleteRecordSchedule': (
              200,
              '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                  '<u:X_DeleteRecordScheduleResponse xmlns:u="urn:schemas-xsrs-org:service:X_ScheduledRecording:2">'
                  '</u:X_DeleteRecordScheduleResponse></s:Body></s:Envelope>',
            ),
          }, onRequest: (r) => seenBody = r.body),
        ),
        controlUrl: xsrsUrl,
      );
      await service.deleteSchedule('10000000000000000004');
      expect(
        seenBody,
        contains('<RecordScheduleID>10000000000000000004</RecordScheduleID>'),
      );
    });

    test('an update without a change field is rejected client-side', () async {
      final service = SoapScheduleService(
        soap: SoapTransport(client: router({})),
        controlUrl: xsrsUrl,
      );
      await expectLater(
        service.updateSchedule(const ScheduleUpdate(id: '1', priorityFlag: 0)),
        throwsA(
          isA<NasneError>().having(
            (e) => e.category,
            'category',
            NasneErrorCategory.validation,
          ),
        ),
      );
    });

    test('conflict fault propagates (no reservation-count fallback)', () async {
      // Phase 1 conclusion: the phase 0 Fault tracked the candidate's
      // compact +0900 datetime, not the reservation count, so the
      // service must not mask Faults from X_GetConflictList.
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: router({
            'X_GetConflictList': (500, soapFixture('conflict_fault.xml')),
            'X_GetRecordScheduleList': (
              200,
              soapFixture('record_schedule_list_empty.xml'),
            ),
          }),
        ),
        controlUrl: xsrsUrl,
      );
      await expectLater(
        service.checkConflicts(
          NewRecordSchedule(
            start: DateTime.parse('2026-11-18T04:00:00+09:00'),
            durationSeconds: 300,
            channel: const ScheduleChannel(
              broadcastingType: 2,
              channelType: 2,
              serviceId: 56832,
            ),
            networkId: 30848,
          ),
        ),
        throwsA(
          isA<NasneError>()
              .having(
                (e) => e.category,
                'category',
                NasneErrorCategory.soapFault,
              )
              .having((e) => e.code, 'code', '402'),
        ),
      );
    });

    test('conflict fault with existing schedules propagates', () async {
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: router({
            'X_GetConflictList': (500, soapFixture('conflict_fault.xml')),
            'X_GetRecordScheduleList': (
              200,
              soapFixture('schedule_list_one.xml'),
            ),
          }),
        ),
        controlUrl: xsrsUrl,
      );
      await expectLater(
        service.checkConflicts(
          NewRecordSchedule(
            start: DateTime.parse('2026-11-18T04:00:00+09:00'),
            durationSeconds: 300,
            channel: const ScheduleChannel(
              broadcastingType: 2,
              channelType: 2,
              serviceId: 56832,
            ),
            networkId: 30848,
          ),
        ),
        throwsA(
          isA<NasneError>()
              .having(
                (e) => e.category,
                'category',
                NasneErrorCategory.soapFault,
              )
              .having((e) => e.code, 'code', '402'),
        ),
      );
    });

    test('conflict list parses items when the call succeeds', () async {
      final service = SoapScheduleService(
        soap: SoapTransport(
          client: router({
            'X_GetConflictList': (200, soapFixture('conflict_ok.xml')),
          }),
        ),
        controlUrl: xsrsUrl,
      );
      final conflicts = await service.checkConflicts(
        NewRecordSchedule(
          start: DateTime.parse('2026-11-18T04:00:00+09:00'),
          durationSeconds: 300,
          channel: const ScheduleChannel(
            broadcastingType: 2,
            channelType: 2,
            serviceId: 56832,
          ),
          networkId: 30848,
        ),
      );
      expect(conflicts.length, 1);
      expect(conflicts.single.id, '10000000000000000004');
    });
  });

  group('SoapTitleCatalogService (XSRS + DIDL join)', () {
    SoapTitleCatalogService build(MockClient client) {
      return SoapTitleCatalogService(
        soap: SoapTransport(client: client),
        xsrsControlUrl: xsrsUrl,
        webApi: WebApiTransport('192.0.2.1', client: client),
        metadata: _FixtureMetadata(),
      );
    }

    test('titles merge DIDL complement by title id', () async {
      final catalog = build(
        router({'X_GetTitleList': (200, soapFixture('title_list.xml'))}),
      );
      final titles = await catalog.listTitles();
      expect(titles.length, 2);
      final t2 = titles.firstWhere((t) => t.id == '10000000000000000002');
      expect(t2.genre, 'ドキュメンタリー／教養');
      expect(t2.copyCountRemaining, 10);
      expect(t2.res.length, 3);
      expect(t2.scheduledDurationSeconds, 854);
      final t1 = titles.firstWhere((t) => t.id == '10000000000000000001');
      expect(t1.genre, '福祉');
      expect(t1.copyCountRemaining, 9);
      expect(t1.resumePointSeconds, 16);
    });

    test('deleteTitle sends X_DeleteTitle with the list-form id', () async {
      late String seenBody;
      final catalog = build(
        router({
          'X_DeleteTitle': (
            200,
            '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                '<u:X_DeleteTitleResponse xmlns:u="urn:schemas-xsrs-org:service:X_ScheduledRecording:2">'
                '</u:X_DeleteTitleResponse></s:Body></s:Envelope>',
          ),
        }, onRequest: (r) => seenBody = r.body),
      );
      await catalog.deleteTitle('10000000000000000001');
      expect(seenBody, contains('<TitleID>10000000000000000001</TitleID>'));
    });

    test('setTitleProtection sends X_UpdateTitle with the listed item, '
        'flag flipped (plan 86.3 / 98)', () async {
      final bodies = <String>[];
      final catalog = build(
        router({
          'X_GetTitleList': (200, soapFixture('title_list.xml')),
          'X_UpdateTitle': (
            200,
            '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
                '<u:X_UpdateTitleResponse xmlns:u="urn:schemas-xsrs-org:service:X_ScheduledRecording:2">'
                '</u:X_UpdateTitleResponse></s:Body></s:Envelope>',
          ),
        }, onRequest: (r) => bodies.add(r.body)),
      );
      final titles = await catalog.listTitles();
      final t1 = titles.firstWhere((t) => t.id == '10000000000000000001');
      expect(t1.protectFlag, isFalse);
      await catalog.setTitleProtection(t1, protect: true);
      final updateBody = bodies.last;
      expect(updateBody, contains('<u:X_UpdateTitle '));
      // The Elements value is the listed item document, escaped
      // for transport, with only the flag changed.
      expect(
        updateBody,
        contains('&lt;titleProtectFlag&gt;1&lt;/titleProtectFlag&gt;'),
      );
      expect(
        updateBody,
        isNot(contains('&lt;titleProtectFlag&gt;0&lt;/titleProtectFlag&gt;')),
      );
      expect(
        updateBody,
        contains('&lt;item id="10000000000000000001"&gt;'),
      );
      expect(updateBody, contains('&lt;portableRecordFile'));
      expect(updateBody, contains('&lt;recordSize&gt;521&lt;/recordSize&gt;'));
    });

    test(
      'setTitleProtection refuses a title with no listed document',
      () async {
        final catalog = build(router({}));
        await expectLater(
          catalog.setTitleProtection(
            const RecordedTitle(id: '9', title: 'x'),
            protect: true,
          ),
          throwsA(
            isA<NasneError>().having(
              (e) => e.category,
              'category',
              NasneErrorCategory.unsupported,
            ),
          ),
        );
      },
    );

    test('setResumePosition posts milliseconds to the media-service '
        'port (plan 102)', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('{"errorcode": 0}', 200);
      });
      final catalog = SoapTitleCatalogService(
        soap: SoapTransport(client: client),
        xsrsControlUrl: xsrsUrl,
        webApi: WebApiTransport('192.0.2.1', client: client),
        metadata: _FixtureMetadata(),
      );
      await catalog.setResumePosition(
        '10000000000000000001',
        const Duration(minutes: 5, milliseconds: 250),
      );
      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'http://192.0.2.1:64220/recorded/recordedContentResumePositionSet',
      );
      expect(seen.body, 'id=10000000000000000001&position=300250');
    });

    test('setResumePosition clamps a negative position to zero '
        '(the unit rejects one with errorcode 803)', () async {
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('{"errorcode": 0}', 200);
      });
      final catalog = SoapTitleCatalogService(
        soap: SoapTransport(client: client),
        xsrsControlUrl: xsrsUrl,
        webApi: WebApiTransport('192.0.2.1', client: client),
        metadata: _FixtureMetadata(),
      );
      await catalog.setResumePosition(
        '10000000000000000001',
        const Duration(seconds: -3),
      );
      expect(seen.body, 'id=10000000000000000001&position=0');
    });
  });
}

class _FixtureMetadata implements MetadataService {
  @override
  Future<DidlDocument> browse(String objectId) async {
    return parseDidl(
      File('test/fixtures/dlna/browse_0_video_all.xml').readAsStringSync(),
      'test',
    );
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
