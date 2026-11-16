/// EPG (programme guide) service (plan 12.8 / 21).
///
/// The acquisition recipe, determined by measurement (plan 21):
/// fetch the binary version table from `status/EPGVersionInfoGet`,
/// send it back three times concatenated as the binary body of
/// `chEpg/EPGGet` (POST, Content-Type: application/binary,
/// X-DTVToken over the body), then deobfuscate (XOR 0x9d) and
/// inflate the response. One call returns the full guide for the
/// broadcasting type (8 days, all services, on the measured unit).
library;

import '../endpoints.dart';
import '../errors.dart';
import '../models/channel.dart';
import '../models/epg.dart';
import '../parsing/epg.dart';
import '../store/registration_store.dart';
import '../transport/webapi_transport.dart';

class WebApiEpgService {
  WebApiEpgService({
    required this._plain,
    required this._authed,
    this._guideCache,
    this._cacheHost,
  });

  final WebApiTransport _plain;
  final WebApiTransport _authed;

  /// Persistent accumulation cache (plan 23). The unit-side EPG
  /// store does not hold basic (title-carrying) sections for every
  /// day of the returned window — measured: the days +1..+3 ahead
  /// arrive with extended sections only, while today (sparse) and
  /// +4..+7 carry the titles. Merging each fetch into a persistent
  /// cache captures a day's titles while that day is in the titled
  /// window, so the guide keeps them when the day rotates into the
  /// title-less window. Null disables accumulation (tests, harness).
  final EpgGuideCache? _guideCache;
  final String? _cacheHost;

  /// Fetches and parses the full programme guide for
  /// [broadcastingType]. [channels] is the type's channel list
  /// (DeviceInfoService.listChannels); sections are anchored on it.
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  ) async {
    final versionTable = await _plain.getBytes(
      WebApiEndpoints.epgVersionInfoGet,
      params: {'broadcastingType': '$broadcastingType'},
    );
    if (versionTable.isEmpty) {
      throw NasneError.parse('webapi:EPGVersionInfoGet',
          cause: 'empty version table');
    }
    // The measured acceptance rule needs the table repeated; three
    // copies put the body past the observed threshold with margin
    // (plan 21). The response is the full dataset, not a delta.
    final body = <int>[
      ...versionTable,
      ...versionTable,
      ...versionTable,
    ];
    final raw = await _authed.postBinary(
      WebApiEndpoints.epgGet,
      body: body,
    );
    final plain = inflateEpgResponse(raw);
    final fresh = parseEpgGuide(plain, channels,
        broadcastingType: broadcastingType);
    final cache = _guideCache;
    final host = _cacheHost;
    if (cache == null || host == null) return fresh;
    // Accumulation is best-effort: a cache failure must never break
    // the guide itself.
    try {
      final cached = await cache.load(host, broadcastingType);
      final merged = mergeEpgGuideWithCache(fresh, cached);
      await cache.save(host, broadcastingType, merged);
      return merged;
    } catch (_) {
      return fresh;
    }
  }

  /// Fetches the channel logos of [broadcastingType] as
  /// serviceId -> PNG bytes (services without a logo are absent).
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType) async {
    final raw = await _plain.getBytes(
      WebApiEndpoints.channelLogoDataGet,
      params: {'broadcastingType': '$broadcastingType'},
    );
    return parseChannelLogos(raw);
  }
}

/// Merges a freshly fetched [fresh] guide with the accumulated
/// [cached] events (serviceId -> events, from [EpgGuideCache]).
///
/// The fresh guide is authoritative: its services, channels and
/// events form the base. For an event present in both (same eventId
/// and start), fields the fresh copy lacks are filled from the
/// cached copy; fresh values always win. Cached events absent from
/// the fresh guide are carried over, except ones that ended more
/// than a day before the fresh guide starts (past data the UI no
/// longer shows; this also bounds the cache size). The result is
/// sorted by start within each service.
EpgGuide mergeEpgGuideWithCache(
  EpgGuide fresh,
  Map<int, List<EpgEvent>> cached,
) {
  if (cached.isEmpty || fresh.services.isEmpty) return fresh;
  final freshFrom = fresh.from;
  if (freshFrom == null) return fresh;
  final cutoff = freshFrom.subtract(const Duration(days: 1));
  (int, int) keyOf(EpgEvent e) =>
      (e.eventId, e.start.microsecondsSinceEpoch);
  return EpgGuide(
    broadcastingType: fresh.broadcastingType,
    services: [
      for (final service in fresh.services)
        EpgServiceGuide(
          channel: service.channel,
          events: _mergeEvents(
            service.events,
            cached[service.channel.serviceId] ?? const [],
            keyOf,
            cutoff,
          ),
        ),
    ],
  );
}

List<EpgEvent> _mergeEvents(
  List<EpgEvent> fresh,
  List<EpgEvent> cached,
  (int, int) Function(EpgEvent) keyOf,
  DateTime cutoff,
) {
  if (cached.isEmpty) return fresh;
  final cachedByKey = {for (final e in cached) keyOf(e): e};
  final freshKeys = {for (final e in fresh) keyOf(e)};
  final merged = <EpgEvent>[
    for (final e in fresh) _fillFrom(e, cachedByKey[keyOf(e)]),
    for (final e in cached)
      if (!freshKeys.contains(keyOf(e)) && e.end.isAfter(cutoff)) e,
  ];
  merged.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.eventId.compareTo(b.eventId);
  });
  return merged;
}

/// [fresh] with each still-null field taken from [cached] (its
/// accumulated twin). Returns [fresh] unchanged when there is no
/// twin or nothing to fill.
EpgEvent _fillFrom(EpgEvent fresh, EpgEvent? cached) {
  if (cached == null) return fresh;
  if (fresh.title != null &&
      fresh.shortText != null &&
      fresh.description != null &&
      fresh.cast != null &&
      fresh.extendedText != null &&
      fresh.extendedItems.isNotEmpty &&
      fresh.genreLevel1 != null &&
      fresh.genreLevel2 != null) {
    return fresh;
  }
  return EpgEvent(
    eventId: fresh.eventId,
    start: fresh.start,
    duration: fresh.duration,
    title: fresh.title ?? cached.title,
    shortText: fresh.shortText ?? cached.shortText,
    description: fresh.description ?? cached.description,
    cast: fresh.cast ?? cached.cast,
    extendedItems:
        fresh.extendedItems.isNotEmpty ? fresh.extendedItems : cached.extendedItems,
    extendedText: fresh.extendedText ?? cached.extendedText,
    genreLevel1: fresh.genreLevel1 ?? cached.genreLevel1,
    genreLevel2: fresh.genreLevel2 ?? cached.genreLevel2,
  );
}
