/// The live channel list under the programme guide's
/// subchannel switch (plan 95): with the switch off,
/// terrestrial subchannels and BS auxiliary services drop
/// out; CS bands and channels without a parsed identity are
/// left alone. The switch itself is the existing one — no new
/// setting was added.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_subchannel_visibility.dart';

LiveChannel liveChannel(
  String band,
  String tag, {
  int? networkId,
  int? transportStreamId,
  int? serviceId,
}) => LiveChannel(
  id: '0/video/LiveTuner/$band/ch?$tag',
  bandId: '0/video/LiveTuner/$band',
  networkId: networkId,
  transportStreamId: transportStreamId,
  serviceId: serviceId,
  programTitle: '番組$tag',
);

LiveBand band(String segment, String title, List<LiveChannel> channels) =>
    LiveBand(
      containerId: '0/video/LiveTuner/$segment',
      title: title,
      channels: channels,
    );

List<String> ids(List<LiveBand> bands) => [
  for (final band in bands)
    for (final channel in band.channels) channel.id,
];

void main() {
  group('liveBandKind', () {
    test('classifies the measured container ids', () {
      expect(liveBandKind(band('DTTB', '地上デジタル', const [])), LiveBandKind.terrestrial);
      expect(liveBandKind(band('BS', 'ＢＳデジタル', const [])), LiveBandKind.bs);
      expect(liveBandKind(band('CS', '１１０度ＣＳ', const [])), LiveBandKind.cs);
      expect(liveBandKind(band('XX', '不明', const [])), LiveBandKind.other);
    });
  });

  group('liveBandsWithSubchannelSetting', () {
    final terrestrial = band('DTTB', '地上デジタル', [
      liveChannel('DTTB', 'a', networkId: 10, transportStreamId: 10, serviceId: 100),
      liveChannel('DTTB', 'b', networkId: 10, transportStreamId: 10, serviceId: 101),
      liveChannel('DTTB', 'c', networkId: 10, transportStreamId: 11, serviceId: 200),
      liveChannel('DTTB', 'noid'),
    ]);

    test('terrestrial: OFF keeps the main channel of each TS', () {
      final result = liveBandsWithSubchannelSetting([terrestrial], false);
      expect(ids(result), [
        terrestrial.channels[0].id,
        terrestrial.channels[2].id,
        terrestrial.channels[3].id,
      ]);
    });

    test('terrestrial: ON returns the bands unchanged', () {
      final result = liveBandsWithSubchannelSetting([terrestrial], true);
      expect(ids(result), ids([terrestrial]));
    });

    test('BS: OFF hides auxiliary services, keeps independent ones', () {
      final bs = band('BS', 'ＢＳデジタル', [
        liveChannel('BS', 'a', networkId: 4, transportStreamId: 1, serviceId: 101),
        liveChannel('BS', 'b', networkId: 4, transportStreamId: 1, serviceId: 102),
        liveChannel('BS', 'c', networkId: 4, transportStreamId: 2, serviceId: 191),
        liveChannel('BS', 'd', networkId: 4, transportStreamId: 2, serviceId: 192),
        liveChannel('BS', 'e', networkId: 4, transportStreamId: 3, serviceId: 232),
        liveChannel('BS', 'f', networkId: 6, transportStreamId: 4, serviceId: 142),
      ]);
      final result = liveBandsWithSubchannelSetting([bs], false);
      expect(ids(result), [
        bs.channels[0].id,
        bs.channels[2].id,
        bs.channels[3].id,
        bs.channels[5].id,
      ]);
    });

    test('CS: OFF leaves the band unchanged', () {
      final cs = band('CS', '１１０度ＣＳ', [
        liveChannel('CS', 'a', networkId: 4, transportStreamId: 1, serviceId: 142),
        liveChannel('CS', 'b', networkId: 4, transportStreamId: 1, serviceId: 143),
      ]);
      final result = liveBandsWithSubchannelSetting([cs], false);
      expect(ids(result), ids([cs]));
    });

    test('band order, titles and empty bands survive filtering', () {
      final empty = band('CS', '１１０度ＣＳ', const []);
      final result = liveBandsWithSubchannelSetting(
        [terrestrial, empty],
        false,
      );
      expect(result.map((b) => b.title), ['地上デジタル', '１１０度ＣＳ']);
      expect(result[1].channels, isEmpty);
    });
  });
}
