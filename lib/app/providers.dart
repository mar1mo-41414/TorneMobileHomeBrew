/// Composition root (plan 12.2 / 12.7): Riverpod providers that wire
/// the domain interfaces to their transport implementations. UI and
/// tests depend on the interfaces only; swapping an implementation
/// (e.g. a mock in tests, or a future transport for a newly
/// discovered path) is an override here, never a UI change.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/core.dart';
import 'ake_socket.dart';
import 'debug_log.dart';
import 'multicast_lock.dart';
import 'wakelock.dart';

final httpClientProvider = Provider<http.Client>((ref) => http.Client());

/// Sleep suppression for the player screen (plan 32, reworked in
/// plan 35): a hand-rolled platform channel flips the OS switch
/// and reads it back, so the debug log shows whether the setting
/// actually stuck.
final wakelockGuardProvider = Provider<WakelockGuard>(
  (ref) => NativeWakelockGuard(),
);

/// The single app-wide wakelock coordinator (plan 35): player
/// screens open sessions on it, and the OS lock is held while
/// any session is playing — one screen ending can no longer drop
/// the lock from under another that is still playing (the
/// build-13 field log showed exactly that).
final playbackWakelockProvider = Provider<PlaybackWakelock>(
  (ref) => PlaybackWakelock(
    guard: ref.watch(wakelockGuardProvider),
    diag: ref.watch(diagLogProvider),
  ),
);

/// Discovery chain (plan 16.3): SSDP first; when it finds nothing
/// (multicast-restricted environments such as iOS sideloading), the
/// unicast subnet scan runs. Manual registration stays available in
/// the settings screen regardless. On Android the SSDP step holds a
/// WifiManager.MulticastLock while searching (plan 17).
final discoveryServiceProvider = Provider<DiscoveryService>(
  (ref) => CompositeDiscoveryService([
    SsdpDiscoveryService(
      client: ref.watch(httpClientProvider),
      lockGuard: MethodChannelMulticastLockGuard(),
    ),
    SubnetScanDiscoveryService(client: ref.watch(httpClientProvider)),
  ]),
);

final registrationServiceProvider = Provider<RegistrationService>(
  (ref) => WebApiRegistrationService(client: ref.watch(httpClientProvider)),
);

/// Defaults to in-memory; the app entry point overrides this with a
/// file-backed store in the documents directory (app/bootstrap.dart).
final registrationStoreProvider = Provider<RegistrationStore>(
  (ref) => InMemoryRegistrationStore(),
);

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => InMemoryKeyValueStore(),
);

final channelCacheProvider = Provider<ChannelCache>(
  (ref) => ChannelCache(ref.watch(keyValueStoreProvider)),
);

/// The DTCP-IP credential vault (Phase 5, plan 26.4). The pair
/// itself is read only by the playback engine; the UI uses the
/// summary provider below.
final credentialStoreProvider =
    Provider<CredentialStore>((ref) => SecureCredentialStore());

/// SRM persistence: signed public data in the regular key-value
/// store (plan 26.4).
final srmStoreProvider = Provider<KeyValueSrmStore>(
  (ref) => KeyValueSrmStore(ref.watch(keyValueStoreProvider)),
);

/// Non-sensitive facts about the imported pair for the settings UI
/// (presence, device ID, certificate fingerprint). Invalidated
/// after import / delete.
final credentialSummaryProvider =
    FutureProvider<CredentialSummary?>((ref) async {
  final credentials = await ref.watch(credentialStoreProvider).load();
  return credentials == null ? null : CredentialSummary.of(credentials);
});

/// Whether the programme guide shows subchannels (plan 25;
/// default off), persisted in the key-value store.
class ShowSubchannelsNotifier extends Notifier<bool> {
  static const _key = 'epg_show_subchannels';

  @override
  bool build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final value = await store.read(_key);
      if (value != null && value == 'true' && !state) state = true;
    });
    return false;
  }

  Future<void> set(bool value) async {
    state = value;
    await ref
        .read(keyValueStoreProvider)
        .write(_key, value ? 'true' : 'false');
  }
}

final showSubchannelsProvider =
    NotifierProvider<ShowSubchannelsNotifier, bool>(
        ShowSubchannelsNotifier.new);

/// The app store directory (file stores and the debug log
/// destination, plan 28; location rule in plan 39).
/// The bootstrap overrides this with the real directory; null in
/// tests / headless contexts (debug logging then stays off).
final storeDirectoryProvider = Provider<Directory?>((ref) => null);

/// Debug mode settings (plan 28): the master switch and the
/// enabled category set, persisted in the key-value store.
class DebugSettingsNotifier extends Notifier<DebugSettings> {
  static const _masterKey = 'debug_mode_enabled';
  static const _categoriesKey = 'debug_categories';

  @override
  DebugSettings build() {
    final store = ref.watch(keyValueStoreProvider);
    Future.microtask(() async {
      final master = await store.read(_masterKey);
      final categories = await store.read(_categoriesKey);
      state = DebugSettings(
        master: master == 'true',
        categories: DebugSettings.decodeCategories(categories),
      );
    });
    return const DebugSettings();
  }

  Future<void> setMaster(bool value) async {
    state = state.copyWith(master: value);
    await ref.read(keyValueStoreProvider).write(_masterKey, '$value');
  }

  Future<void> setCategory(DiagCategory category, bool enabled) async {
    final next = {...state.categories};
    if (enabled) {
      next.add(category);
    } else {
      next.remove(category);
    }
    state = state.copyWith(categories: next);
    await ref
        .read(keyValueStoreProvider)
        .write(_categoriesKey, state.encodeCategories());
  }
}

final debugSettingsProvider =
    NotifierProvider<DebugSettingsNotifier, DebugSettings>(
        DebugSettingsNotifier.new);

/// The app-wide diagnostics logger (plan 28). Reflects the current
/// debug settings on every record: master off, the category off,
/// or no store directory records nothing.
final diagLogProvider = Provider<DiagLog>((ref) {
  final dir = ref.watch(storeDirectoryProvider);
  if (dir == null) return const DiagLog.none();
  final sink = FileDebugLogSink(dir);
  return DiagLog(
    (category, message) => sink.write(category, message),
    (category) {
      final settings = ref.read(debugSettingsProvider);
      return settings.master && settings.categories.contains(category);
    },
  );
});

final playbackEngineProvider = Provider<PlaybackEngine>(
  (ref) => DtcpPlaybackEngine(
    credentialStore: ref.watch(credentialStoreProvider),
    srmStore: ref.watch(srmStoreProvider),
    diag: ref.watch(diagLogProvider),
    akeConnectionFactory: (host, port) =>
        nativeAkeConnectionFactory(host, port, diag: ref.read(diagLogProvider)),
  ),
);

/// The per-device service bundle, assembled from a registration.
/// Control URLs come from [NasneDevice.direct] (the measured
/// fallback forms, plan 11.6) unless a described device is supplied.
class DeviceServices {
  const DeviceServices({
    required this.deviceInfo,
    required this.settings,
    required this.schedules,
    required this.titles,
    required this.metadata,
    required this.playback,
  });

  final DeviceInfoService deviceInfo;
  final SettingsService settings;
  final ScheduleService schedules;
  final TitleCatalogService titles;
  final MetadataService metadata;
  final PlaybackEngine playback;
}

DeviceServices assembleDeviceServices(
  RegisteredNasne reg, {
  NasneDevice? describedDevice,
  http.Client? client,
  KeyValueStore? keyValueStore,
  CredentialStore? credentialStore,
  SrmStore? srmStore,
  DiagLog? diagLog,
}) {
  final device = describedDevice ?? NasneDevice.direct(reg.host);
  final plain = WebApiTransport(reg.host, client: client);
  final authed = WebApiTransport(reg.host,
      client: client, tokenProvider: reg.tokenProvider);
  final soap = SoapTransport(client: client);
  final xsrs = device.controlUrl(SoapServices.scheduledRecording.serviceType);
  final cds = device.controlUrl(SoapServices.contentDirectory.serviceType);
  if (xsrs == null || cds == null) {
    throw NasneError.validation(
        'providers', 'device exposes no XSRS/ContentDirectory control URL');
  }
  final metadata = CompositeMetadataService(
    dlna: DlnaMetadataService(soap: soap, controlUrl: cds),
    epg: WebApiEpgService(
      plain: plain,
      authed: authed,
      diag: diagLog ?? const DiagLog.none(),
      // Persistent guide accumulation (plan 23), backed by the
      // app's key-value store when one is wired.
      guideCache:
          keyValueStore == null ? null : EpgGuideCache(keyValueStore),
      cacheHost: reg.host,
    ),
  );
  return DeviceServices(
    deviceInfo: WebApiDeviceInfoService(plain),
    settings: WebApiSettingsService(authed),
    schedules: SoapScheduleService(soap: soap, controlUrl: xsrs),
    titles: SoapTitleCatalogService(
      soap: soap,
      xsrsControlUrl: xsrs,
      webApi: plain,
      metadata: metadata,
    ),
    metadata: metadata,
    playback: DtcpPlaybackEngine(
      credentialStore: credentialStore ?? SecureCredentialStore(),
      srmStore: srmStore ??
          KeyValueSrmStore(keyValueStore ?? InMemoryKeyValueStore()),
      diag: diagLog ?? const DiagLog.none(),
      akeConnectionFactory: (host, port) => nativeAkeConnectionFactory(
        host,
        port,
        diag: diagLog ?? const DiagLog.none(),
      ),
    ),
  );
}

final deviceServicesProvider = Provider.family<DeviceServices, RegisteredNasne>(
  (ref, reg) => assembleDeviceServices(
    reg,
    client: ref.watch(httpClientProvider),
    keyValueStore: ref.watch(keyValueStoreProvider),
    credentialStore: ref.watch(credentialStoreProvider),
    srmStore: ref.watch(srmStoreProvider),
    diagLog: ref.watch(diagLogProvider),
  ),
);
