/// Live channel model (plan 39): one channel of the DMS
/// `0/video/LiveTuner` tree, carrying the programme currently on
/// air as the DIDL item advertises it. The stream itself is a
/// DTCP-IP resource exactly like a recording's (same res list,
/// same AKE path); only the locator differs (`/web/video/ch`
/// instead of `/web/video/pvr`).
library;

import 'title.dart';

/// One band container of the LiveTuner tree (terrestrial / BS /
/// CS), with its channels in the device's order.
class LiveBand {
  const LiveBand({
    required this.containerId,
    required this.title,
    required this.channels,
  });

  /// DIDL container id, e.g. `0/video/LiveTuner/DTTB`.
  final String containerId;

  /// The band name as the device advertises it (地上デジタル /
  /// ＢＳデジタル / １１０度ＣＳ in the measured tree).
  final String title;

  final List<LiveChannel> channels;
}

/// A live channel and its current programme.
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.bandId,
    this.networkId,
    this.transportStreamId,
    this.serviceId,
    this.channelName,
    this.channelNr,
    this.genre,
    required this.programTitle,
    this.description,
    this.longDescription,
    this.programStart,
    this.programEnd,
    this.res = const [],
  });

  /// DIDL item id, e.g.
  /// `0/video/LiveTuner/DTTB/ch?nid=7880&tsid=7880&svid=de00`.
  final String id;

  /// The band container id this channel was listed under.
  final String bandId;

  /// Channel identity, parsed from the item id's hex parameters
  /// (the same (nid, tsid, sid) space as `channelListGet`,
  /// plan 39). Null when the id does not carry them.
  final int? networkId;
  final int? transportStreamId;
  final int? serviceId;

  /// `upnp:channelName`, e.g. `ＮＨＫ総合１・北九州`.
  final String? channelName;

  /// `upnp:channelNr` (raw; its numbering space is the DIDL one,
  /// not the remote-control key number).
  final int? channelNr;

  /// `upnp:genre` of the current programme.
  final String? genre;

  /// The programme currently on air (`dc:title` of the item).
  final String programTitle;
  final String? description;
  final String? longDescription;

  /// `upnp:scheduledStartTime` / `scheduledEndTime` of the
  /// current programme, as advertised when the item was listed.
  /// The programme boundary passes without the item changing
  /// under the app, so these go stale until the list is
  /// refreshed (plan 39).
  final DateTime? programStart;
  final DateTime? programEnd;

  /// The channel's stream resources (dr / x3 / mobile), same
  /// shape as a recording's.
  final List<TitleRes> res;

  /// The original-quality resource (plan 33 selection, shared
  /// with recorded titles).
  TitleRes? get originalRes => res.originalRes;

  /// The mobile (low-bitrate) resource, when offered.
  TitleRes? get mobileRes => res.mobileRes;
}
