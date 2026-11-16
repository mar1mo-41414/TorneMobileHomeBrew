/// DIDL-Lite models (ContentDirectory Browse results, plan 11.8).
library;

import 'title.dart';

/// A DIDL container (folder) entry.
class DidlContainer {
  const DidlContainer({
    required this.id,
    required this.parentId,
    required this.title,
    this.childCount,
  });

  final String id;
  final String parentId;
  final String title;
  final int? childCount;
}

/// A DIDL item entry (one recorded title's metadata view).
class DidlItem {
  const DidlItem({
    required this.id,
    required this.parentId,
    required this.title,
    this.date,
    this.description,
    this.longDescription,
    this.channelName,
    this.channelNr,
    this.copyCountRemaining,
    this.res = const [],
    this.properties = const {},
  });

  /// Full DIDL id, e.g. `0/video/all/pvr?id=17947967890000000002`.
  final String id;
  final String parentId;
  final String title;

  /// The title id extracted from [id] (the join key with XSRS,
  /// plan 12.5). Null when the id does not carry one.
  String? get titleId {
    final marker = 'pvr?id=';
    final i = id.indexOf(marker);
    if (i < 0) return null;
    final rest = id.substring(i + marker.length);
    final end = rest.indexOf('&');
    return end < 0 ? rest : rest.substring(0, end);
  }

  final String? date;
  final String? description;
  final String? longDescription;
  final String? channelName;
  final int? channelNr;

  /// `av:COGCount`.
  final int? copyCountRemaining;
  final List<TitleRes> res;

  /// Any other element text, keyed by qualified element name.
  final Map<String, String> properties;
}

/// A parsed DIDL-Lite document.
class DidlDocument {
  const DidlDocument({required this.containers, required this.items});

  final List<DidlContainer> containers;
  final List<DidlItem> items;
}
