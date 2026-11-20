/// Programme search over the held EPG dataset (plan 86,
/// plan 85 item 8).
///
/// The guide screen is a grid the viewer scans by eye; the
/// official torne mobile's other main path into a programme
/// is search — by keyword and by genre (plan 85.4, sourced).
/// The app already holds eight days of EPG per band (the
/// dataset behind the guide providers), so the search is a
/// pure client-side filter over that data: no new requests,
/// nothing extra asked of the nasne.
///
/// Matching is a plain substring test over the fields a
/// viewer would search by — the programme title, its short
/// text, its description, its cast, and the channel name —
/// case-insensitively. The genre filter compares the ARIB
/// content descriptor's level-1 nibble the parser already
/// extracts (EpgEvent.genreLevel1). Hits come back in start
/// order across all bands and channels, earliest first.
library;

import '../core/core.dart';

/// One search hit: an event and the service (channel) it
/// belongs to, which the result list shows and the detail
/// dialog's reservation path needs.
class EpgSearchHit {
  const EpgSearchHit({required this.service, required this.event});

  final EpgServiceGuide service;
  final EpgEvent event;

  Channel get channel => service.channel;
  String get channelName => service.channel.serviceName;
}

/// The ARIB genre level-1 label for the search filter's
/// choices. (The full genre table — labels and tile colours
/// — belongs to plan 86 item 10; the names defined there
/// replace these when it lands.)
String epgSearchGenreLabel(int genreLevel1) => switch (genreLevel1) {
  0 => 'ニュース・報道',
  1 => 'スポーツ',
  2 => '情報・ワイドショー',
  3 => 'ドラマ',
  4 => '音楽',
  5 => 'バラエティ',
  6 => '映画',
  7 => 'アニメ・特撮',
  8 => 'ドキュメンタリー・教養',
  9 => '劇場・公演',
  10 => '趣味・教育',
  11 => '福祉',
  12 || 13 => '予備',
  14 => '拡張',
  15 => 'その他',
  _ => 'ジャンル $genreLevel1',
};

/// The genre level-1 values actually present in [guides],
/// ascending — the filter offers only genres the viewer
/// could actually hit.
List<int> epgSearchGenreValues(List<EpgGuide> guides) {
  final values = <int>{};
  for (final guide in guides) {
    for (final service in guide.services) {
      for (final event in service.events) {
        final genre = event.genreLevel1;
        if (genre != null) values.add(genre);
      }
    }
  }
  return values.toList()..sort();
}

/// Searches [guides] (every band the app holds) for events
/// matching [query] and, when given, [genreLevel1].
///
/// An empty (or whitespace-only) query matches every event,
/// so a genre alone can drive the search; the screen only
/// runs the search once the viewer has entered one of the
/// two. Results are sorted by start time, earliest first,
/// across bands and channels alike.
List<EpgSearchHit> searchEpgProgrammes({
  required List<EpgGuide> guides,
  String query = '',
  int? genreLevel1,
}) {
  final needle = query.trim().toLowerCase();
  final hits = <EpgSearchHit>[];
  for (final guide in guides) {
    for (final service in guide.services) {
      for (final event in service.events) {
        if (genreLevel1 != null && event.genreLevel1 != genreLevel1) {
          continue;
        }
        if (needle.isNotEmpty &&
            !_matchesQuery(event, service.channel.serviceName, needle)) {
          continue;
        }
        hits.add(EpgSearchHit(service: service, event: event));
      }
    }
  }
  hits.sort((a, b) => a.event.start.compareTo(b.event.start));
  return hits;
}

bool _matchesQuery(EpgEvent event, String channelName, String needle) {
  bool inField(String? field) =>
      field != null && field.toLowerCase().contains(needle);
  return inField(event.title) ||
      inField(event.shortText) ||
      inField(event.description) ||
      inField(event.cast) ||
      inField(channelName);
}
