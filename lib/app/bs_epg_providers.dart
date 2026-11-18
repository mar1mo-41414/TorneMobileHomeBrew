/// BS EPG providers, preserving the existing terrestrial data path.
/// Terrestrial providers remain unchanged, including their cache keys.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'providers.dart';

/// Measured nasne WebAPI broadcastingType for BS digital television.
const int bsBroadcastingType = 3;

final bsChannelsProvider = FutureProvider.family<List<Channel>, RegisteredNasne>(
  (ref, reg) async {
    final service = ref.watch(deviceServicesProvider(reg)).deviceInfo;
    final cache = ref.watch(channelCacheProvider);
    try {
      final channels = await service.listChannels(bsBroadcastingType);
      await cache.save(reg.host, bsBroadcastingType, channels);
      return channels;
    } on NasneError {
      final cached = await cache.load(reg.host, bsBroadcastingType);
      if (cached != null) return cached;
      rethrow;
    }
  },
);

final bsEpgGuideProvider = FutureProvider.family<EpgGuide, RegisteredNasne>(
  (ref, reg) async {
    final channels = await ref.watch(bsChannelsProvider(reg).future);
    return ref
        .watch(deviceServicesProvider(reg))
        .metadata
        .getProgrammeGuide(bsBroadcastingType, channels);
  },
);

final bsChannelLogosProvider =
    FutureProvider.family<Map<int, List<int>>, RegisteredNasne>(
  (ref, reg) async {
    try {
      return await ref
          .watch(deviceServicesProvider(reg))
          .metadata
          .getChannelLogos(bsBroadcastingType);
    } on NasneError {
      return const {};
    }
  },
);
