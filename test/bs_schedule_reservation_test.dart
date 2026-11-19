/// Channel selection regression tests for BS EPG -> XSRS reservations.
/// All samples are synthetic. No nasne calls or real reservations.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/schedule_channel_selection.dart';

const terrestrial = Channel(
  broadcastingType: 2,
  networkId: 30848,
  transportStreamId: 101,
  serviceId: 103,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト地デジ',
);
const bs = Channel(
  broadcastingType: 3,
  networkId: 4,
  transportStreamId: 18227,
  serviceId: 244,
  serviceType: 1,
  channelNumber: 244,
  serviceName: 'テストBS',
);
const otherBs = Channel(
  broadcastingType: 3,
  networkId: 4,
  transportStreamId: 12345,
  serviceId: 244,
  serviceType: 1,
  channelNumber: 244,
  serviceName: '別TSの同一SID',
);

void main() {
  test('BS prefill resolves the original full network/TS/service triple', () {
    final key = initialScheduleChannelKey(
      [bs, otherBs],
      3,
      scheduleChannelKey(bs),
      prefill: bs,
    );
    expect(resolveScheduleChannel([bs, otherBs], 3, key), same(bs));
  });

  test('missing BS station never selects a terrestrial station', () {
    final key = initialScheduleChannelKey(
      [terrestrial],
      3,
      scheduleChannelKey(bs),
      prefill: bs,
    );
    expect(key, isNull);
    expect(resolveScheduleChannel([terrestrial], 3, key), isNull);
  });

  test('same serviceId on another BS TS cannot impersonate prefill', () {
    final key = initialScheduleChannelKey(
      [otherBs],
      3,
      scheduleChannelKey(bs),
      prefill: bs,
    );
    expect(key, isNull);
  });

  test('manual terrestrial form preserves its first-channel default', () {
    final key = initialScheduleChannelKey(
      [terrestrial],
      2,
      null,
      defaultToFirst: true,
    );
    expect(resolveScheduleChannel([terrestrial], 2, key), same(terrestrial));
  });

  test('XSRS time-change preselects only an unambiguous BS service', () {
    const original = ScheduleChannel(
      broadcastingType: 3,
      channelType: 3,
      serviceId: 244,
    );
    expect(
      initialScheduleChannelKey([bs], 3, null, original: original),
      scheduleChannelKey(bs),
    );
    expect(
      initialScheduleChannelKey([bs, otherBs], 3, null, original: original),
      isNull,
    );
  });

  test('BS create XML carries BS type, SID, network and EPG event', () {
    final candidate = NewRecordSchedule(
      start: DateTime.utc(2026, 11, 18, 2, 0),
      durationSeconds: 3900,
      channel: const ScheduleChannel(
        broadcastingType: 3,
        channelType: 3,
        serviceId: 244,
      ),
      networkId: 4,
      eventId: 0x12ab,
    );
    final xml = buildCreateItemXml(candidate);
    expect(xml, contains('broadcastingType="3"'));
    expect(xml, contains('channelType="3"'));
    expect(xml, contains('0x00f4'));
    expect(xml, contains('0x0004'));
    expect(xml, contains('0x12ab'));
  });
}
