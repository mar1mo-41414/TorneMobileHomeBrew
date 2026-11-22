/// Reserved marking for the programme guide (plan 120):
/// the desiredMatchingID event-id parse, the reservation
/// index's matching rules, and the guide grid framing a
/// reserved event's tile in red while an unreserved tile
/// stays unframed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_reserved.dart';
import 'package:tmhb/ui/epg_screen.dart';

RecordSchedule _schedule({
  String id = '1',
  required DateTime start,
  int broadcastingType = 2,
  int serviceId = 0x3333,
  String desiredMatchingId = '',
}) => RecordSchedule(
  id: id,
  start: start,
  durationSeconds: 1800,
  conditionId: '1',
  channel: ScheduleChannel(
    broadcastingType: broadcastingType,
    channelType: 2,
    serviceId: serviceId,
  ),
  desiredQualityMode: 100,
  desiredMatchingId: desiredMatchingId,
  reservationCreatorId: '2000',
  priorityFlag: 0,
  recordDestinationId: 'HDD',
);

const _channel = Channel(
  broadcastingType: 2,
  networkId: 0x1111,
  transportStreamId: 0x2222,
  serviceId: 0x3333,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト局',
);

void main() {
  group('desiredMatchingEventId', () {
    test('reads the event id of the server-normalised list form', () {
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,0x1234'), 0x1234);
      expect(desiredMatchingEventId('0x1111,0x2222,0x3333,0x0007'), 7);
    });

    test('reads the event id of the create form', () {
      expect(desiredMatchingEventId(',,0x1111,0x00AB'), 0xAB);
    });

    test('a manual reservation carries event id 0', () {
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,0x0000'), 0);
    });

    test('unparseable values give null', () {
      expect(desiredMatchingEventId(''), isNull);
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00'), isNull);
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,'), isNull);
      expect(desiredMatchingEventId('0x7880,0x7880,0xDE00,0xZZZZ'), isNull);
    });
  });

  group('EpgReservedIndex', () {
    final start = DateTime.utc(2026, 11, 23, 12, 0);
    final event = EpgEvent(
      eventId: 7,
      start: start,
      duration: const Duration(minutes: 30),
      title: '番組',
    );

    test('an event reservation matches by event id, whatever its start', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start.add(const Duration(minutes: 3)),
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
        ),
      ]);
      expect(index.isReserved(_channel, event), isTrue);
    });

    test('a manual reservation matches by start instant', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0000',
        ),
      ]);
      expect(index.isReserved(_channel, event), isTrue);
    });

    test('a manual reservation starting a minute off does not match', () {
      final index = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start.add(const Duration(minutes: 1)),
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0000',
        ),
      ]);
      expect(index.isReserved(_channel, event), isFalse);
    });

    test('another service or band does not match', () {
      final byService = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          serviceId: 0x4444,
          desiredMatchingId: '0x1111,0x2222,0x4444,0x0007',
        ),
      ]);
      expect(byService.isReserved(_channel, event), isFalse);
      final byBand = EpgReservedIndex.fromSchedules([
        _schedule(
          start: start,
          broadcastingType: 3,
          desiredMatchingId: '0x1111,0x2222,0x3333,0x0007',
        ),
      ]);
      expect(byBand.isReserved(_channel, event), isFalse);
    });

    test('no reservations, no marking', () {
      final index = EpgReservedIndex.fromSchedules(const []);
      expect(index.isEmpty, isTrue);
      expect(index.isReserved(_channel, event), isFalse);
    });
  });

  group('epgReservedFrame', () {
    test('a reserved tile gets the red frame; others get none', () {
      final frame = epgReservedFrame(true);
      expect(frame, isNotNull);
      final border = frame!.border as Border;
      expect(border.top.color, epgReservedFrameColor);
      expect(border.top.width, epgReservedFrameWidth);
      expect(epgReservedFrame(false), isNull);
    });
  });

  group('guide grid', () {
    testWidgets('a reserved event tile is framed; an unreserved one is not', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const reg = RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:test',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      final now = DateTime.now().toUtc();
      final guide = EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: _channel,
            events: [
              EpgEvent(
                eventId: 1,
                start: now,
                duration: const Duration(minutes: 30),
                title: '予約済み番組',
                genreLevel1: 3,
              ),
              EpgEvent(
                eventId: 2,
                start: now.add(const Duration(hours: 1)),
                duration: const Duration(minutes: 30),
                title: '通常番組',
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
              InMemoryRegistrationStore(const [reg]),
            ),
            epgGuideProvider.overrideWith((ref, r) async => guide),
            channelLogosProvider.overrideWith(
              (ref, r) async => const <int, List<int>>{},
            ),
            schedulesProvider.overrideWith(
              (ref, r) async => [
                _schedule(
                  start: now,
                  desiredMatchingId: '0x1111,0x2222,0x3333,0x0001',
                ),
              ],
            ),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Container frameOf(String title) => tester.widget<Container>(
        find
            .ancestor(of: find.text(title), matching: find.byType(Container))
            .first,
      );
      final reserved = frameOf('予約済み番組');
      expect(reserved.foregroundDecoration, isNotNull);
      final decoration = reserved.foregroundDecoration! as BoxDecoration;
      final border = decoration.border! as Border;
      expect(border.top.color, epgReservedFrameColor);
      expect(frameOf('通常番組').foregroundDecoration, isNull);
    });
  });
}
