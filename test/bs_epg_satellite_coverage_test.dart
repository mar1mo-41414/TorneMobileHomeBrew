/// Regression coverage for BS EPG service version table gaps and missing EIT.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

Channel bs(int sid, {int tsid = 0x4422, int serviceType = 1}) => Channel(
  broadcastingType: 3,
  networkId: 4,
  transportStreamId: tsid,
  serviceId: sid,
  serviceType: serviceType,
  channelNumber: sid,
  serviceName: 'BS $sid',
);

void putRecord(List<int> data, int index, int sid, int flags,
    {int tsid = 0x4422}) {
  final p = 12 + 144 * index;
  data[p] = 0;
  data[p + 1] = 4;
  data[p + 2] = tsid >> 8;
  data[p + 3] = tsid & 0xff;
  data[p + 4] = sid >> 8;
  data[p + 5] = sid & 0xff;
  data[p + 6] = flags >> 8;
  data[p + 7] = flags & 0xff;
}

void main() {
  test('BS scanner skips gaps and accepts later real services with non-c000 flags', () {
    // An inactive gap interrupts the original terrestrial scanner.
    final table = List<int>.filled(12 + 144 * 5 + 8, 0xff);
    putRecord(table, 0, 193, 0xc000);
    putRecord(table, 2, 244, 0xa000);
    putRecord(table, 3, 999, 0xc000); // not in channelListGet
    putRecord(table, 4, 191, 0x8000);
    final channels = [bs(191), bs(193), bs(244), bs(245)];
    expect(parseSatelliteEpgVersionServices(table, channels), const [
      EpgServiceRef(4, 0x4422, 193),
      EpgServiceRef(4, 0x4422, 244),
      EpgServiceRef(4, 0x4422, 191),
    ]);
    // The existing terrestrial parser still stops at the first gap.
    expect(parseEpgVersionServices(table), const [
      EpgServiceRef(4, 0x4422, 193),
    ]);
    expect(buildEpgGetBody(
        parseSatelliteEpgVersionServices(table, channels)).length, 8 + 24 * 3);
  });

  test('BS all channel columns stay visible, but missing EIT remains empty', () {
    final channels = [bs(191), bs(192), bs(193), bs(244)];
    final original = EpgGuide(broadcastingType: 3, services: [
      EpgServiceGuide(channel: channels.first, events: const []),
    ]);
    final completed = completeBsEpgGuide(original, channels);
    expect(completed.services.map((s) => s.channel.serviceId),
        [191, 192, 193, 244]);
    expect(completed.eventCount, 0);
    expect(completed.services[2].events, isEmpty);
    expect(completed.services[3].events, isEmpty);
  });

  test('terrestrial guide is unchanged by the BS coverage helper', () {
    final original = EpgGuide(broadcastingType: 2, services: const []);
    expect(identical(completeBsEpgGuide(original, [bs(193)]), original), isTrue);
  });

  test('BS scanner ignores bogus triples and non-video channels', () {
    final table = List<int>.filled(12 + 144 * 2 + 8, 0xff);
    putRecord(table, 0, 193, 0xc000);
    putRecord(table, 1, 244, 0xa000);
    final result = parseSatelliteEpgVersionServices(
        table, [bs(193, serviceType: 192), bs(244)]);
    expect(result, const [EpgServiceRef(4, 0x4422, 244)]);
  });
}
