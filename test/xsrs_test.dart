/// xsrs parsing / building against the masked phase 0 fixtures.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

String soapFixture(String name) =>
    File('test/fixtures/soap/$name').readAsStringSync();

/// Extracts the (entity-escaped) Result of a fixture envelope and
/// un-escapes it the same way the SOAP transport does via innerText.
String resultOf(String envelope) {
  final match = RegExp(r'<Result>(.*?)</Result>', dotAll: true)
      .firstMatch(envelope);
  final raw = match!.group(1)!;
  return raw
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}

void main() {
  group('schedule list parsing', () {
    test('empty list fixture parses to zero items', () {
      final items = parseXsrsItems(
          resultOf(soapFixture('record_schedule_list_empty.xml')),
          'test');
      expect(items, isEmpty);
    });

    test('one-item fixture converts with measured semantics', () {
      final items = parseXsrsItems(
          resultOf(soapFixture('schedule_list_one.xml')), 'test');
      expect(items.length, 1);
      final s = recordScheduleFromXsrs(items.single, source: 'test');
      expect(s.id, '10000000000000000004');
      expect(s.start, DateTime.parse('2026-11-18T04:00:00+09:00'));
      expect(s.durationSeconds, 300);
      expect(s.conditionId, '1'); // server-normalised from empty
      expect(s.channel.serviceId, 56832);
      expect(s.channel.broadcastingType, 2);
      expect(s.desiredQualityMode, 100);
      // Server-normalised 4-element matching id.
      expect(s.desiredMatchingId, '0x7880,0x7880,0xDE00,0x0000');
      expect(s.matchingIdType, 'SI_PROGRAMID');
      expect(s.recordDestinationId, 'HDD');
    });
  });

  group('title list parsing', () {
    test('two items with resume points and genres', () {
      final items =
          parseXsrsItems(resultOf(soapFixture('title_list.xml')), 'test');
      expect(items.length, 2);
      final t1 = recordedTitleFromXsrs(items[0], source: 'test');
      expect(t1.id, '10000000000000000001');
      expect(t1.title, startsWith('テスト番組タイトル'));
      expect(t1.scheduledDurationSeconds, 298);
      expect(t1.genreId, '180');
      expect(t1.genreType, 2);
      expect(t1.resumePointSeconds, 16);
      expect(t1.recordSizeRaw, 521);
      final t2 = recordedTitleFromXsrs(items[1], source: 'test');
      expect(t2.id, '10000000000000000002');
      expect(t2.scheduledDurationSeconds, 854);
      expect(t2.resumePointSeconds, 14);
    });
  });

  group('id normalisation (the 803 trap, plan 11.7)', () {
    test('strips the literal 0x prefix over the decimal id', () {
      expect(normalizeScheduleId('0x10000000000000000003'),
          '10000000000000000003');
      expect(normalizeScheduleId('10000000000000000003'),
          '10000000000000000003');
    });
  });

  group('builders', () {
    test('create item is the full torne template (no title element)',
        () {
      final xml = buildCreateItemXml(NewRecordSchedule(
        start: DateTime.parse('2026-11-18T04:00:00+09:00'),
        durationSeconds: 300,
        channel: const ScheduleChannel(
            broadcastingType: 2, channelType: 2, serviceId: 56832),
        networkId: 30848,
      ));
      expect(xml, contains('<scheduledStartDateTime>2026-11-18T04:00:00+09:00</scheduledStartDateTime>'));
      expect(xml, contains('<scheduledChannelID broadcastingType="2" channelType="2">0xde00</scheduledChannelID>'));
      expect(xml, contains('<desiredMatchingID type="SI_PROGRAMID">,,0x7880,0x0000</desiredMatchingID>'));
      expect(xml, contains('<scheduledConditionID></scheduledConditionID>'));
      expect(xml, isNot(contains('<title>')));
    });

    test('update item is sparse', () {
      final xml = buildUpdateItemXml(const ScheduleUpdate(
        id: '42',
        priorityFlag: 1,
      ));
      expect(xml, contains('<item id="42">'));
      expect(xml, contains('<priorityFlag>1</priorityFlag>'));
      expect(xml, isNot(contains('scheduledStartDateTime')));
      expect(xml, isNot(contains('desiredQualityMode')));
    });
  });
}
