/// Search, sort and filtering for the recorded title list
/// (plan 86.5). Pure view logic over the merged [RecordedTitle]
/// list: the screen holds the user's choices, this file decides
/// what they mean. Before this the list was the raw fetch order
/// with no way to find anything in it (plan 85 item 5).
library;

import '../core/models/title.dart';

/// Sort orders offered above the title list.
enum TitleSortOrder {
  recordedNewest('新しい順'),
  recordedOldest('古い順'),
  titleAsc('番組名順');

  const TitleSortOrder(this.label);

  final String label;
}

/// The user's search / filter choices for the title list.
class TitleListFilter {
  const TitleListFilter({
    this.query = '',
    this.channelKey,
    this.genre,
    this.unwatchedOnly = false,
  });

  /// Title substring to match (case-insensitive); empty matches all.
  final String query;

  /// Channel grouping key (see [titleChannelKey]); null = all.
  final String? channelKey;

  /// DIDL genre text; null = all.
  final String? genre;

  /// Only titles the unit still flags as new (unwatched).
  final bool unwatchedOnly;

  bool get isActive =>
      query.trim().isNotEmpty ||
      channelKey != null ||
      genre != null ||
      unwatchedOnly;
}

/// The channel a title is grouped and filtered by: the DIDL
/// channel name when the merge provided one, else the XSRS
/// service in the same fallback form the detail view shows.
String? titleChannelKey(RecordedTitle title) {
  final name = title.channelName;
  if (name != null && name.isNotEmpty) return name;
  final channel = title.channel;
  if (channel != null) return 'サービス ${channel.serviceIdHex}';
  return null;
}

/// Distinct channel keys present in [titles], sorted for display.
List<String> titleChannelChoices(List<RecordedTitle> titles) {
  final keys = <String>{for (final t in titles) ?titleChannelKey(t)};
  return keys.toList()..sort();
}

/// Distinct genre texts present in [titles], sorted for display.
List<String> titleGenreChoices(List<RecordedTitle> titles) {
  final genres = <String>{
    for (final t in titles)
      if (t.genre case final genre? when genre.isNotEmpty) genre,
  };
  return genres.toList()..sort();
}

/// Applies [filter] and [sort] to [titles]; the input list is
/// not modified. Undated titles sort last in both date orders,
/// so a missing timestamp never floats to the top.
List<RecordedTitle> applyTitleListView(
  List<RecordedTitle> titles, {
  required TitleListFilter filter,
  required TitleSortOrder sort,
}) {
  final query = filter.query.trim().toLowerCase();
  final result = [
    for (final t in titles)
      if ((query.isEmpty || t.title.toLowerCase().contains(query)) &&
          (filter.channelKey == null ||
              titleChannelKey(t) == filter.channelKey) &&
          (filter.genre == null || t.genre == filter.genre) &&
          (!filter.unwatchedOnly || t.newFlag))
        t,
  ];
  int byTitle(RecordedTitle a, RecordedTitle b) {
    final c = a.title.compareTo(b.title);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  int byDate(RecordedTitle a, RecordedTitle b, {required bool newestFirst}) {
    final ad = a.scheduledStart;
    final bd = b.scheduledStart;
    if (ad == null && bd == null) return byTitle(a, b);
    if (ad == null) return 1;
    if (bd == null) return -1;
    final c = newestFirst ? bd.compareTo(ad) : ad.compareTo(bd);
    return c != 0 ? c : byTitle(a, b);
  }

  result.sort(switch (sort) {
    TitleSortOrder.recordedNewest => (a, b) => byDate(a, b, newestFirst: true),
    TitleSortOrder.recordedOldest => (a, b) => byDate(a, b, newestFirst: false),
    TitleSortOrder.titleAsc => byTitle,
  });
  return result;
}
