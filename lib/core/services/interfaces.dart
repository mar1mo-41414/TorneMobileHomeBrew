/// Domain service interfaces (plan 5.0 / 12.2).
///
/// UI and domain logic depend only on these interfaces; the concrete
/// transports (SSDP / WebAPI JSON / UPnP SOAP / DLNA) live behind the
/// implementations and can be replaced without touching callers.
library;

import '../models/device.dart';
import '../models/didl.dart';
import '../models/epg.dart';
import '../models/live_status.dart';
import '../models/channel.dart';
import '../models/schedule.dart';
import '../models/title.dart';

/// SSDP discovery + description-based identification (plan 5.2 / 12.1).
abstract interface class DiscoveryService {
  /// Scans the LAN for nasne devices. Identification is by device
  /// description content, never by SSDP headers alone (plan 11.2).
  Future<List<NasneDevice>> discover({Duration timeout});

  /// Fetches and parses a device description from [location]
  /// (an SSDP LOCATION URL or a manually entered device root).
  Future<NasneDevice> describe(Uri location);
}

/// Registration flow: description -> MAC -> PIN derivation ->
/// PINVerify (plan 5.2 / 11.5).
abstract interface class RegistrationService {
  /// Runs the full registration against [device] and returns the
  /// record to persist. Throws a NasneError when verification fails.
  Future<RegisteredNasne> register(NasneDevice device);

  /// Re-verifies an existing registration (PINVerify only).
  Future<bool> verify(RegisteredNasne registration);
}

/// Read-side device information (WebAPI `status/*`, plan 12.1).
abstract interface class DeviceInfoService {
  Future<DeviceInfo> getDeviceInfo();
  Future<List<HddEntry>> listHdds();
  Future<HddInfo> getHddInfo(int id);
  Future<NetworkInfo> getNetworkInfo();
  Future<BcasInfo> getBcasInfo();
  Future<List<Channel>> listChannels(int broadcastingType);
  Future<LiveStatus> getLiveStatus();
  Future<List<RecNgItem>> listRecNg();
  Future<ClientInfo> getClientInfo();
}

/// Reservations (UPnP SOAP X_ScheduledRecording, plan 12.1 / 12.3).
abstract interface class ScheduleService {
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  });

  /// Creates a reservation from the full template. Returns the
  /// normalised (list-form) id of the created reservation.
  Future<String> createSchedule(NewRecordSchedule schedule);

  /// Applies a sparse update. Start time and duration are not
  /// updatable (plan 12.5); callers model a time change as
  /// delete + create.
  Future<void> updateSchedule(ScheduleUpdate update);

  /// Deletes by canonical (list-form) id.
  Future<void> deleteSchedule(String id);

  /// Checks a candidate reservation for conflicts, returning the
  /// conflicting existing reservations (empty when none).
  Future<List<RecordSchedule>> checkConflicts(NewRecordSchedule candidate);
}

/// Recorded titles: XSRS primary, WebAPI counts, DIDL complement
/// (plan 12.1 / 12.5). Callers only see the merged model.
abstract interface class TitleCatalogService {
  Future<List<RecordedTitle>> listTitles({bool withMetadata = true});
  Future<int> countTitles();
  Future<int> maxTitles();
}

/// Settings reads and the verified writes (WebAPI, plan 12.1).
/// Writes go through the token-authenticated POST path.
abstract interface class SettingsService {
  Future<String> getBoxName();
  Future<int> getMobileBitrate();
  Future<void> setBoxName(String name);
  Future<void> setMobileBitrate(int bitrateInfo);
}

/// DLNA ContentDirectory Browse (plan 12.1) and the programme
/// guide behind the same boundary (plan 12.8 / 21).
abstract interface class MetadataService {
  /// The container holding all recordings (plan 11.8).
  static const String allRecordingsContainer = '0/video/all';

  Future<DidlDocument> browse(String objectId);

  /// The full EPG programme guide for a broadcasting type
  /// (terrestrial = 2), anchored on the type's channel list.
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  );

  /// Channel logos of a broadcasting type: serviceId -> PNG bytes.
  /// Services without a logo are absent from the map.
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType);
}

/// A running playback session (Phase 5): the player reads the
/// decrypted stream from [mediaUri] (a loopback URL) until [stop]
/// tears the session down.
abstract interface class PlaybackSession {
  Uri get mediaUri;
  Future<void> stop();
}

/// Playback boundary (plan 5.7). v1 shipped only the stub, which
/// reports [NasneErrorCategory.unsupported]; Phase 5 substitutes
/// the DTCP-IP engine (plan 26) behind the same boundary.
abstract interface class PlaybackEngine {
  bool get isSupported;

  /// Starts playback of [title] via [res] and returns the live
  /// session. The v1 stub always throws a NasneError of category
  /// `unsupported`; the DTCP-IP engine throws `validation` when no
  /// credential pair has been imported.
  Future<PlaybackSession> startPlayback(RecordedTitle title, TitleRes res);
}
