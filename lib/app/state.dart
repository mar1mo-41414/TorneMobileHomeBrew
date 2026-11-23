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
/// plan 9 item 5c). The selection is persisted in the key-value
/// store so it survives restarts when several devices are
/// registered; without it a restart always fell back to the
/// first registered device.
class SelectedHostNotifier extends Notifier<String?> {
  static const _key = 'selected_host';

  @override
  String? build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      if (value != null && state == null) state = value;
    });
    return null;
  }

  Future<void> select(String? host) async {
    state = host;
    final store = ref.read(keyValueStoreProvider);
    if (host == null) {
      await store.delete(_key);
    } else {
      await store.write(_key, host);
    }
  }
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

/// One HDD list entry together with its detail (null when the
/// entry is not mounted/registered or the detail fetch failed;
/// the entry alone still renders).
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
        // An entry that is not mounted or not registered has no
        // detail to fetch (the endpoint fails for it, plan 116);
        // the tile renders such an external entry as not
        // connected instead of as a fetch failure.
        if (entry.mounted && entry.registered) {
          try {
            info = await service.getHddInfo(entry.id);
          } on NasneError {
            info = null;
          }
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
///
/// The whole list is read, paging past the service's 50-item page:
/// the device holds up to 100 reservations, and a consumer that
/// only saw the first page would silently miss the rest (the
/// guide's reserved marking, plan 120, is one such consumer).
/// Paging stops at a short page, or at a page that adds no new
/// reservation id — the second rule keeps doubles that ignore
/// paging from looping forever.
final schedulesProvider =
    FutureProvider.family<List<RecordSchedule>, RegisteredNasne>((
      ref,
      reg,
    ) async {
      final service = ref.watch(deviceServicesProvider(reg)).schedules;
      final all = <RecordSchedule>[];
      final seen = <String>{};
      var index = 0;
      while (true) {
        final page = await service.listSchedules(
          startingIndex: index,
          requestedCount: 50,
        );
        var added = 0;
        for (final s in page) {
          if (seen.add(s.id)) {
            all.add(s);
            added++;
          }
        }
        if (page.length < 50 || added == 0) break;
        index += page.length;
      }
      return all..sort((a, b) => a.start.compareTo(b.start));
    });

/// Recorded titles, loaded progressively (plan 100): the stream
/// emits the titles fetched so far — a first chunk, then page by
/// page — and a final stage marked complete once every page is
/// in and the DIDL complement is merged. Only the complete
/// stage is the whole list; consumers that search, filter or
/// sort (whole-set operations) must treat an incomplete stage
/// as provisional.
///
/// A notifier rather than a plain stream provider so a
/// successful protection update can rewrite the one title's
/// flag in the loaded list (plan 103, [TitlesNotifier.applyProtection])
/// and a successful resume report can rewrite the one title's
/// resume point (plan 104, [TitlesNotifier.applyResumePoint]),
/// instead of refetching the whole list: the refetch cost grows
/// with the library, and the unit's own list can lag the update
/// anyway.
class TitlesNotifier extends StreamNotifier<TitleListProgress> {
  TitlesNotifier(this.reg);

  final RegisteredNasne reg;

  @override
  Stream<TitleListProgress> build() =>
      ref.watch(deviceServicesProvider(reg)).titles.listTitlesProgressively();

  /// Rewrites the protection flag of the loaded title [titleId]
  /// in place, after the unit accepted the update (plan 103).
  ///
  /// The list the UI holds becomes the up-to-date one at once:
  /// the row's lock icon and the detail's switch both read this
  /// state, so neither waits for — or is clobbered by — a
  /// refetch. A later stream stage or an explicit refresh still
  /// replaces the state with what the unit answers; that is the
  /// unit's list catching up, not a state this patch defends.
  /// Does nothing while no stage has loaded, or when the title
  /// is not in the loaded stage.
  void applyProtection(String titleId, bool protect) {
    final stage = state.value;
    if (stage == null) return;
    final i = stage.titles.indexWhere((t) => t.id == titleId);
    if (i < 0 || stage.titles[i].protectFlag == protect) return;
    final titles = [...stage.titles];
    titles[i] = titles[i].withProtectFlag(protect);
    state = AsyncData(TitleListProgress(titles, complete: stage.complete));
  }

  /// Rewrites the resume point of the loaded title [titleId]
  /// in place, after the unit accepted the resume report a
  /// closing player made (plan 104 follow-up).
  ///
  /// The detail's resume row and the resume choice at the
  /// next play both read this state, so they follow the
  /// viewing that just ended instead of the snapshot from
  /// before it: without the patch, a position the unit
  /// already held looked unrecorded until a manual refresh.
  /// A reported zero (the viewing ran to the end) clears
  /// the point. The stamp moves with the point — the unit
  /// re-stamps lastPlaybackTime on every accepted report
  /// (plan 102). Does nothing while no stage has loaded, or
  /// when the title is not in the loaded stage.
  void applyResumePoint(String titleId, int resumePointSeconds) {
    final stage = state.value;
    if (stage == null) return;
    final i = stage.titles.indexWhere((t) => t.id == titleId);
    if (i < 0 || stage.titles[i].resumePointSeconds == resumePointSeconds) {
      return;
    }
    final titles = [...stage.titles];
    titles[i] = titles[i].withResumePoint(resumePointSeconds, DateTime.now());
    state = AsyncData(TitleListProgress(titles, complete: stage.complete));
  }
}

final titlesProvider =
    StreamNotifierProvider.family<
      TitlesNotifier,
      TitleListProgress,
      RegisteredNasne
    >(TitlesNotifier.new);

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

/// Deletes [schedule] on [reg]'s device and invalidates the
/// reservation list, so every consumer of it — the schedules
/// tab, the guide's reserved marking (plan 120) — repaints
/// from the device. Used by the guide detail's delete action
/// on a reserved event (plan 124); the schedules tab keeps
/// its own flow, which also pops its detail pane.
Future<void> deleteScheduleAndInvalidate(
  WidgetRef ref,
  RegisteredNasne reg,
  RecordSchedule schedule,
) async {
  await ref
      .read(deviceServicesProvider(reg))
      .schedules
      .deleteSchedule(schedule.id);
  ref.invalidate(schedulesProvider(reg));
}
