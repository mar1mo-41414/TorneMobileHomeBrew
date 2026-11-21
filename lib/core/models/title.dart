/// Recorded title model (plan 12.5): XSRS item as the primary source,
/// DIDL (ContentDirectory Browse) as the complement. The join is done
/// inside TitleCatalogService; the UI only ever sees this merged model.
library;

import 'schedule.dart';

/// One `res` element of a DIDL item: a (future) playback locator.
///
/// Kept in full for the future playback engine (plan 1.4 / 5.7):
/// URL, protocolInfo, and the DTCP connection parameters parsed out
/// of it.
class TitleRes {
  const TitleRes({
    required this.url,
    required this.protocolInfo,
    this.dtcpHost,
    this.dtcpPort,
    this.duration,
    this.cleartextSize,
    this.quality,
  });

  final String url;
  final String protocolInfo;

  /// DTCP1HOST from protocolInfo (the AKE target host).
  final String? dtcpHost;

  /// DTCP1PORT from protocolInfo (dynamic per session, plan 11.8).
  final int? dtcpPort;

  final Duration? duration;

  /// `dlna:cleartextSize` attribute (bytes, pre-encryption size).
  final int? cleartextSize;

  /// The `quality` query value of the res URL (dr / mobile / ...).
  final String? quality;
}

/// A recorded title.
class RecordedTitle {
  const RecordedTitle({
    required this.id,
    required this.title,
    this.scheduledStart,
    this.scheduledDurationSeconds,
    this.channel,
    this.desiredQualityMode,
    this.genreId,
    this.genreType,
    this.reservationCreatorId,
    this.protectFlag = false,
    this.newFlag = false,
    this.recordingFlag = false,
    this.recordDestinationId,
    this.recordSizeRaw,
    this.lastPlaybackTime,
    this.resumePointSeconds,
    this.sourceItemXml,
    this.description,
    this.longDescription,
    this.channelName,
    this.genre,
    this.copyCountRemaining,
    this.res = const [],
  });

  /// XSRS item id (also the join key with DIDL, plan 12.5).
  final String id;
  final String title;
  final DateTime? scheduledStart;
  final int? scheduledDurationSeconds;
  final ScheduleChannel? channel;
  final int? desiredQualityMode;
  final String? genreId;
  final int? genreType;
  final String? reservationCreatorId;
  final bool protectFlag;
  final bool newFlag;
  final bool recordingFlag;
  final String? recordDestinationId;

  /// XSRS `recordSize`. Its unit is undetermined (plan 12.5): kept raw,
  /// never used for size display (DIDL cleartextSize is preferred).
  final int? recordSizeRaw;

  final DateTime? lastPlaybackTime;

  /// Resume position in seconds, from the `resumePoint` attribute of
  /// `lastPlaybackTime` (plan 12.5).
  final int? resumePointSeconds;

  /// The XSRS `item` element exactly as listed, retained so an
  /// X_UpdateTitle call can send the listed document back with a
  /// single field changed (the device-verified protection toggle,
  /// plan 86.3 / 98). Null for titles that did not come from a
  /// title-list response.
  final String? sourceItemXml;

  // -- DIDL complement --
  final String? description;
  final String? longDescription;
  final String? channelName;

  /// Genre text from DIDL `upnp:genre` (the primary genre when
  /// the item carries several).
  final String? genre;

  /// Remaining copy count, DIDL `av:COGCount` (measured value 10).
  final int? copyCountRemaining;
  final List<TitleRes> res;

  RecordedTitle withDidl({
    String? description,
    String? longDescription,
    String? channelName,
    String? genre,
    int? copyCountRemaining,
    List<TitleRes>? res,
  }) {
    return RecordedTitle(
      id: id,
      title: title,
      scheduledStart: scheduledStart,
      scheduledDurationSeconds: scheduledDurationSeconds,
      channel: channel,
      desiredQualityMode: desiredQualityMode,
      genreId: genreId,
      genreType: genreType,
      reservationCreatorId: reservationCreatorId,
      protectFlag: protectFlag,
      newFlag: newFlag,
      recordingFlag: recordingFlag,
      recordDestinationId: recordDestinationId,
      recordSizeRaw: recordSizeRaw,
      lastPlaybackTime: lastPlaybackTime,
      resumePointSeconds: resumePointSeconds,
      sourceItemXml: sourceItemXml,
      description: description ?? this.description,
      longDescription: longDescription ?? this.longDescription,
      channelName: channelName ?? this.channelName,
      genre: genre ?? this.genre,
      copyCountRemaining: copyCountRemaining ?? this.copyCountRemaining,
      res: res ?? this.res,
    );
  }

  /// A copy of this title with only the protection flag changed.
  ///
  /// Used to reflect a successful protection update in the loaded
  /// list at once (plan 102): the unit accepted the new flag, so
  /// the copy the UI holds can be brought in line without waiting
  /// for a refetch — the unit's own title list can keep answering
  /// with the pre-update flag for a while.
  RecordedTitle withProtectFlag(bool protect) {
    return RecordedTitle(
      id: id,
      title: title,
      scheduledStart: scheduledStart,
      scheduledDurationSeconds: scheduledDurationSeconds,
      channel: channel,
      desiredQualityMode: desiredQualityMode,
      genreId: genreId,
      genreType: genreType,
      reservationCreatorId: reservationCreatorId,
      protectFlag: protect,
      newFlag: newFlag,
      recordingFlag: recordingFlag,
      recordDestinationId: recordDestinationId,
      recordSizeRaw: recordSizeRaw,
      lastPlaybackTime: lastPlaybackTime,
      resumePointSeconds: resumePointSeconds,
      sourceItemXml: sourceItemXml,
      description: description,
      longDescription: longDescription,
      channelName: channelName,
      genre: genre,
      copyCountRemaining: copyCountRemaining,
      res: res,
    );
  }

  /// The original-quality resource (plan 33; selection logic in
  /// [TitleResListSelection], shared with live channels).
  TitleRes? get originalRes => res.originalRes;

  /// The mobile (low-bitrate) resource, when offered (plan 33).
  TitleRes? get mobileRes => res.mobileRes;
}

/// One stage of a progressive title-list load (plan 100).
///
/// [titles] is everything fetched so far, in fetch order. The
/// DIDL complement (channel name, genre, copy count, resources)
/// is merged only in the final stage, so earlier stages carry
/// the XSRS fields alone. [complete] is false until that final
/// stage: search, filtering and sorting are whole-set
/// operations, so a view must not present an incomplete stage's
/// filtered result as the final answer.
class TitleListProgress {
  const TitleListProgress(this.titles, {required this.complete});

  final List<RecordedTitle> titles;
  final bool complete;
}

/// Playback resource selection over a DIDL res list (plan 33),
/// shared by recorded titles and live channels (plan 39): both
/// carry the same dr / x3 / mobile resource family.
extension TitleResListSelection on List<TitleRes> {
  /// The original-quality resource: the content's own quality
  /// (DR / 3倍 / …), i.e. the first res that is not the mobile
  /// transcode. Falls back to the first res when every res is
  /// mobile, and is null when the list is empty.
  TitleRes? get originalRes {
    for (final r in this) {
      if (r.quality != 'mobile') return r;
    }
    return isEmpty ? null : first;
  }

  /// The mobile (low-bitrate) resource, when the nasne offers one
  /// alongside the original. Null when it does not, in which case
  /// the UI offers no quality choice.
  TitleRes? get mobileRes {
    for (final r in this) {
      if (r.quality == 'mobile') return r;
    }
    return null;
  }
}
