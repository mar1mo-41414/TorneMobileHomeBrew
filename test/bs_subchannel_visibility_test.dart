/// Regression tests for the existing "サブチャンネルを表示" setting on BS.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_subchannel_visibility.dart';

Channel channel(int id, {
  int broadcastingType = 3,
  int networkId = 4,
  int tsid = 100,
  int serviceType = 1,
}) => Channel(
  broadcastingType: broadcastingType,
  networkId: networkId,
  transportStreamId: tsid,
  serviceId: id,
  serviceType: serviceType,
  channelNumber: id,
  serviceName: 'service $id',
);

EpgGuide guide(int band, List<Channel> channels) => EpgGuide(
  broadcastingType: band,
  services: [
    for (final ch in channels)
      EpgServiceGuide(channel: ch, events: const []),
  ],
);

List<int> ids(EpgGuide guide) => [
  for (final service in guide.services) service.channel.serviceId,
];

void main() {
  test('BS: OFF hides known auxiliary services but keeps independent channels', () {
    final original = guide(3, [
      channel(101), channel(102),
      channel(141), channel(142), channel(143),
      channel(151), channel(152),
      channel(161), channel(162),
      channel(171), channel(172),
      channel(181), channel(182),
      channel(191), channel(192), channel(193),
      channel(200), channel(201), channel(202),
      channel(231), channel(232), channel(233),
    ]);
    expect(ids(guideWithSubchannelSetting(original, false)), [
      101, 141, 151, 161, 171, 181, 191, 192, 193,
      200, 201, 202, 231,
    ]);
    expect(ids(guideWithSubchannelSetting(original, true)),
        ids(original));
  });

  test('BS: non-video services and other network IDs are not suppressed', () {
    expect(bsSubchannelServiceIds([
      channel(142, serviceType: 192),
      channel(143, networkId: 9),
      channel(144, broadcastingType: 2),
      channel(152),
    ]), {152});
  });

  test('Terrestrial: original same-transport subchannel rule is unchanged', () {
    final original = guide(2, [
      channel(1000, broadcastingType: 2, networkId: 30848, tsid: 100),
      channel(1001, broadcastingType: 2, networkId: 30848, tsid: 100),
      channel(1010, broadcastingType: 2, networkId: 30848, tsid: 101),
    ]);
    expect(ids(guideWithSubchannelSetting(original, false)), [1000, 1010]);
    expect(ids(guideWithSubchannelSetting(original, true)),
        [1000, 1001, 1010]);
  });

  test('CS: do not apply the terrestrial/BS auxiliary service rule', () {
    final original = guide(4, [
      channel(141, broadcastingType: 4),
      channel(142, broadcastingType: 4),
    ]);
    expect(ids(guideWithSubchannelSetting(original, false)), [141, 142]);
  });
}
