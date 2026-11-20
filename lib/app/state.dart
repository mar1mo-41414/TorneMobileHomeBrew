/// App-level state (plan 12.7): the registration list, the selected
/// device, the current tab, and the per-device data providers.
///
/// Everything UI-facing goes through the domain interfaces assembled
/// by the composition root (app/providers.dart); these providers only
/// add caching, selection, and refresh semantics on top. Tests can
/// substitute fakes by overriding the composition-root providers.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'providers.dart';

/// Tab indices of the app shell (plan 5.6; live viewing added
/// in plan 39).
abstract final class AppTabs {
  static const int home = 0;
  static const int live = 1;
  static const int schedules = 2;
  static const int titles = 3;
  static const int epg = 4;
  static const int settings = 5;
}

/// The WebAPI broadcasting type of terrestrial digital (measured,
/// plan 11.4: 0/1 are rejected with 400 on FW 2.60).
const int terrestrialBroadcastingType = 2;

/// The persisted registration list, loaded from the store.
class RegistrationsNotifier extends AsyncNotifier<List<RegisteredNasne>> {
  @override
  Future<List<RegisteredNasne>> build() =>
      ref.watch(registrationStoreProvider).loadAll();

  Future<void> add(RegisteredNasne registration) async {
    await ref.read(registrationStoreProvider).save(registration);
    ref.invalidateSelf();
    await future;
  }

  Future<void> remove(String host) async {
    await ref.read(registrationStoreProvider).remove(host);
    ref.invalidateSelf();
    await future;
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }
}

final registrationsProvider =
    AsyncNotifierProvider<RegistrationsNotifier, List<RegisteredNasne>>(
      RegistrationsNotifier.new,
    );

/// Host of the device the user explicitly selected; null means
/// "the first registered device" (the v1 UI is single-device,
/// plan 9 item 5c).
class SelectedHostNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? host) => state = host;
}

final selectedHostProvider = NotifierProvider<SelectedHostNotifier, String?>(
  SelectedHostNotifier.new,
);

/// The registration the UI currently operates on.
final selectedRegistrationProvider = Provider<RegisteredNasne?>((ref) {
  final registrations = ref.watch(registrationsProvider).value;
  if (registrations == null || registrations.isEmpty) return null;
  final host = ref.watch(selectedHostProvider);
  for (final r in registrations) {
    if (r.host == host) return r;
  }
  return registrations.first;
});

/// The current tab of the app shell; screens may request a switch
/// (e.g. the home screen's "go register" prompt).
class TabIndexNotifier extends Notifier<int> {
  @override
  int build() => AppTabs.home;

  void select(int index) => state = index;
}

final tabIndexProvider = NotifierProvider<TabIndexNotifier, int>(
  TabIndexNotifier.new,
);

// ---------------------------------------------------------------------------
// Per-device data providers. The device is the truth; these are
// display fetches with manual refresh via ref.invalidate (plan 12.7).
// ---------------------------------------------------------------------------

final deviceInfoProvider = FutureProvider.family<DeviceInfo, RegisteredNasne>(
  (ref, reg) =>
      ref.watch(deviceServicesProvider(reg)).deviceInfo.getDeviceInfo(),
);

/// One HDD list entry together with its detail (null when the detail
/// fetch failed; the entry alone still renders).
class HddDetail {
  const HddDetail(this.entry, this.info);

  final HddEntry entry;
  final HddInfo? info;
}

final hddDetailsProvider =
    FutureProvider.family<List<HddDetail>, RegisteredNasne>((ref, reg) async {
      final service = ref.watch(deviceServicesProvider(reg)).deviceInfo;
      final entries = await service.listHdds();
      final details = <HddDetail>[];
      for (final entry in entries) {
        HddInfo? info;
        try {
          info = await service.getHddInfo(entry.id);
        } on NasneError {
          info = null;
        }
        details.add(HddDetail(entry, info));
      }
      return details;
    });

final liveStatusProvider = FutureProvider.family<LiveStatus, RegisteredNasne>(
  (ref, reg) =>
      ref.watch(deviceServicesProvider(reg)).deviceInfo.getLiveStatus(),
);

final recNgProvider = FutureProvider.family<List<RecNgItem>, RegisteredNasne>(
  (ref, reg) => ref.watch(deviceServicesProvider(reg)).deviceInfo.listRecNg(),
);

final networkInfoProvider = FutureProvider.family<NetworkInfo, RegisteredNasne>(
  (ref, reg) =>
      ref.watch(deviceServicesProvider(reg)).deviceInfo.getNetworkInfo(),
);

final bcasInfoProvider = FutureProvider.family<BcasInfo, RegisteredNasne>(
  (ref, reg) => ref.watch(deviceServicesProvider(reg)).deviceInfo.getBcasInfo(),
);

/// Terrestrial channel list, persisted through the channel cache.
/// A network failure falls back to the cached list when one exists.
final channelsProvider = FutureProvider.family<List<Channel>, RegisteredNasne>((
  ref,
  reg,
) async {
  final service = ref.watch(deviceServicesProvider(reg)).deviceInfo;
  final cache = ref.watch(channelCacheProvider);
  try {
    final channels = await service.listChannels(terrestrialBroadcastingType);
    await cache.save(reg.host, terrestrialBroadcastingType, channels);
    return channels;
  } on NasneError {
    final cached = await cache.load(reg.host, terrestrialBroadcastingType);
    if (cached != null) return cached;
    rethrow;
  }
});

/// The full programme guide (terrestrial), anchored on the channel
/// list (plan 21). Fetched as one dataset (8 days on the measured
/// unit); the screen slices it by day.
final epgGuideProvider = FutureProvider.family<EpgGuide, RegisteredNasne>((
  ref,
  reg,
) async {
  final channels = await ref.watch(channelsProvider(reg).future);
  return ref
      .watch(deviceServicesProvider(reg))
      .metadata
      .getProgrammeGuide(terrestrialBroadcastingType, channels);
});

/// Channel logos (terrestrial): serviceId -> PNG bytes (plan 21).
/// A logo failure must not sink the guide, so errors degrade to an
/// empty map.
final channelLogosProvider =
    FutureProvider.family<Map<int, List<int>>, RegisteredNasne>((
      ref,
      reg,
    ) async {
      try {
        return await ref
            .watch(deviceServicesProvider(reg))
            .metadata
            .getChannelLogos(terrestrialBroadcastingType);
      } on NasneError {
        return const {};
      }
    });

/// Reservations in chronological order (the device returns them in
/// its own order; the UI contract is time order, plan 5.6).
final schedulesProvider =
    FutureProvider.family<List<RecordSchedule>, RegisteredNasne>((
      ref,
      reg,
    ) async {
      final list = await ref
          .watch(deviceServicesProvider(reg))
          .schedules
          .listSchedules();
      return [...list]..sort((a, b) => a.start.compareTo(b.start));
    });

final titlesProvider =
    FutureProvider.family<List<RecordedTitle>, RegisteredNasne>(
      (ref, reg) => ref.watch(deviceServicesProvider(reg)).titles.listTitles(),
    );

/// A recorded title's thumbnail image (plan 86.6), fetched
/// lazily per title when its row or detail is shown; null when
/// the unit offers none. Keyed by a record so the family cache
/// is per (device, title).
final titleThumbnailProvider =
    FutureProvider.family<Uint8List?, ({RegisteredNasne reg, String titleId})>(
      (ref, key) => ref
          .watch(deviceServicesProvider(key.reg))
          .titles
          .fetchThumbnail(key.titleId),
    );

/// Live bands and channels with the programme currently on air
/// (plan 39). The programme information is a snapshot of the
/// fetch moment; the screen's refresh action re-fetches it.
final liveChannelsProvider =
    FutureProvider.family<List<LiveBand>, RegisteredNasne>(
      (ref, reg) =>
          ref.watch(deviceServicesProvider(reg)).live.listLiveChannels(),
    );

/// Recorded-title counts (current / maximum).
class TitleCounts {
  const TitleCounts(this.count, this.max);

  final int count;
  final int max;
}

final titleCountsProvider = FutureProvider.family<TitleCounts, RegisteredNasne>(
  (ref, reg) async {
    final service = ref.watch(deviceServicesProvider(reg)).titles;
    return TitleCounts(await service.countTitles(), await service.maxTitles());
  },
);

/// Invalidates every per-device data provider for [reg]; used by the
/// refresh actions. The device stays the source of truth.
void invalidateDeviceData(WidgetRef ref, RegisteredNasne reg) {
  ref.invalidate(deviceInfoProvider(reg));
  ref.invalidate(hddDetailsProvider(reg));
  ref.invalidate(liveStatusProvider(reg));
  ref.invalidate(recNgProvider(reg));
  ref.invalidate(networkInfoProvider(reg));
  ref.invalidate(bcasInfoProvider(reg));
  ref.invalidate(channelsProvider(reg));
  ref.invalidate(epgGuideProvider(reg));
  ref.invalidate(channelLogosProvider(reg));
  ref.invalidate(schedulesProvider(reg));
  ref.invalidate(titlesProvider(reg));
  ref.invalidate(titleCountsProvider(reg));
  ref.invalidate(liveChannelsProvider(reg));
}
