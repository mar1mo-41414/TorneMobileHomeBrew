/// Applies the existing EPG subchannel switch to terrestrial and BS guides,
/// and to the live channel list (plan 95: the same switch, no new setting).
///
/// Terrestrial channels use the original per-transport-stream heuristic.
/// BS channels use explicitly identified auxiliary service IDs instead:
/// unrelated BS channels may share a transport stream.
library;

import '../core/core.dart';

/// BS multichannel IDs (secondary/tertiary services), not all BS services
/// sharing the same transport stream. In particular, WOWOW 191-193 and
/// BS10 200-202 are independent services and must remain visible.
bool _isBsAuxiliaryServiceId(int id) =>
    id == 102 ||
    id == 104 ||
    (id >= 142 && id <= 149) ||
    (id >= 152 && id <= 159) ||
    (id >= 162 && id <= 169) ||
    (id >= 172 && id <= 179) ||
    (id >= 182 && id <= 189) ||
    id == 232 ||
    id == 233;

Set<int> bsSubchannelServiceIds(List<Channel> channels) => {
  for (final ch in channels)
    if (ch.broadcastingType == 3 &&
        ch.networkId == 4 &&
        ch.serviceType == 1 &&
        _isBsAuxiliaryServiceId(ch.serviceId))
      ch.serviceId,
};

/// Which broadcasting band a LiveTuner band container is, from
/// the last segment of its DIDL container id (the measured tree:
/// `0/video/LiveTuner/DTTB` / `.../BS` / `.../CS`, plan 39).
enum LiveBandKind { terrestrial, bs, cs, other }

LiveBandKind liveBandKind(LiveBand band) =>
    switch (band.containerId.split('/').last) {
      'DTTB' => LiveBandKind.terrestrial,
      'BS' => LiveBandKind.bs,
      'CS' => LiveBandKind.cs,
      _ => LiveBandKind.other,
    };

/// Hides only secondary channels when the user has disabled the setting.
/// Other bands (including CS) are left unchanged until verified separately.
EpgGuide guideWithSubchannelSetting(EpgGuide guide, bool showSubchannels) {
  if (showSubchannels) return guide;

  final channels = guide.services.map((s) => s.channel).toList();
  final hiddenIds = switch (guide.broadcastingType) {
    2 => subchannelServiceIds(channels),
    3 => bsSubchannelServiceIds(channels),
    _ => const <int>{},
  };
  if (hiddenIds.isEmpty) return guide;
  return EpgGuide(
    broadcastingType: guide.broadcastingType,
    services: guide.services
        .where((s) => !hiddenIds.contains(s.channel.serviceId))
        .toList(),
  );
}

/// The live channel list under the same subchannel switch as
/// the guide (Discord request, 2026-11-21): with the switch
/// off, terrestrial subchannels and BS auxiliary services drop
/// out of their bands. CS and unrecognised bands are left
/// unchanged, like the guide. Channels whose DIDL id carried
/// no (network, transport stream, service) identity cannot be
/// classified and stay visible.
List<LiveBand> liveBandsWithSubchannelSetting(
  List<LiveBand> bands,
  bool showSubchannels,
) {
  if (showSubchannels) return bands;
  return [
    for (final band in bands)
      LiveBand(
        containerId: band.containerId,
        title: band.title,
        channels: switch (liveBandKind(band)) {
          LiveBandKind.terrestrial => _terrestrialMainChannels(band.channels),
          LiveBandKind.bs => [
            for (final channel in band.channels)
              if (!_isBsAuxiliaryLiveChannel(channel)) channel,
          ],
          _ => band.channels,
        },
      ),
  ];
}

/// The terrestrial rule of [subchannelServiceIds] over live
/// channels: within a (networkId, transportStreamId) group the
/// lowest serviceId is the main channel, the rest are
/// subchannels.
List<LiveChannel> _terrestrialMainChannels(List<LiveChannel> channels) {
  final groups = <(int, int), List<LiveChannel>>{};
  for (final channel in channels) {
    final networkId = channel.networkId;
    final tsId = channel.transportStreamId;
    if (networkId == null || tsId == null || channel.serviceId == null) {
      continue;
    }
    groups.putIfAbsent((networkId, tsId), () => []).add(channel);
  }
  final hiddenIds = <String>{};
  for (final group in groups.values) {
    if (group.length < 2) continue;
    var mainServiceId = group.first.serviceId!;
    for (final channel in group) {
      if (channel.serviceId! < mainServiceId) {
        mainServiceId = channel.serviceId!;
      }
    }
    for (final channel in group) {
      if (channel.serviceId != mainServiceId) hiddenIds.add(channel.id);
    }
  }
  if (hiddenIds.isEmpty) return channels;
  return [
    for (final channel in channels)
      if (!hiddenIds.contains(channel.id)) channel,
  ];
}

/// The BS auxiliary-service rule over live channels. Live items
/// carry no serviceType, so the (networkId 4, auxiliary
/// serviceId) pair of [bsSubchannelServiceIds] is applied
/// as-is: the LiveTuner tree lists viewing services only.
bool _isBsAuxiliaryLiveChannel(LiveChannel channel) =>
    channel.networkId == 4 &&
    channel.serviceId != null &&
    _isBsAuxiliaryServiceId(channel.serviceId!);
