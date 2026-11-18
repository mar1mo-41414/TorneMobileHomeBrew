/// Applies the existing EPG subchannel switch to terrestrial and BS guides.
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
