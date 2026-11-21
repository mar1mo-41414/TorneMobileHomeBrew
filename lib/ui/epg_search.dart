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
///
/// Plan 98: the screen searches through [EpgSearchIndex],
/// built once per dataset. Searching the raw guides on every
/// keystroke re-walked both bands (some sixteen thousand
/// events) and lowercased every searchable field of every
/// event each time — the measured worst case was ~17 ms of
/// UI-thread work per keystroke on a desktop-class CPU,
/// several times that on a phone. The index pays the
/// lowercase pass and the start-order sort once, when the
/// dataset changes; a search over it is a filter.
library;

import '../core/core.dart';
import 'epg_genre.dart';

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
/// choices. The names resolve through the shared genre
/// table (epg_genre.dart, plan 86 item 10); a value the
/// table does not name (the reserved / extension ranges)
/// falls back to a numbered label, since the filter only
/// offers genres actually present in the data.
String epgSearchGenreLabel(int genreLevel1) =>
    epgGenreLabel(genreLevel1) ?? 'ジャンル $genreLevel1';

/// The genre level-1 values actually present in [guides],
/// ascending — the filter offers only genres the viewer
/// could actually hit.
List<int> epgSearchGenreValues(List<EpgGuide> guides) =>
    EpgSearchIndex.fromGuides(guides).genreValues;

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
  return EpgSearchIndex.fromGuides(guides)
      .search(query: query, genreLevel1: genreLevel1);
}

/// A search-ready view of an EPG dataset (plan 98): every
/// event of every band, in start order, with its searchable
/// text pre-lowercased and the dataset's genre values
/// collected — all computed once, at build time.
///
/// The searchable text joins the fields a viewer searches
/// by with newlines, so a query matches exactly the events
/// the per-field test matched (a typed query cannot contain
/// a newline, so nothing matches across a field boundary
/// that would not have matched inside a field).
class EpgSearchIndex {
  factory EpgSearchIndex.fromGuides(List<EpgGuide> guides) {
    final entries = <_IndexedEvent>[];
    final genres = <int>{};
    for (final guide in guides) {
      for (final service in guide.services) {
        for (final event in service.events) {
          final genre = event.genreLevel1;
          if (genre != null) genres.add(genre);
          entries.add(
            _IndexedEvent(
              service: service,
              event: event,
              searchText: _searchTextOf(event, service.channel.serviceName),
            ),
          );
        }
      }
    }
    entries.sort((a, b) => a.event.start.compareTo(b.event.start));
    return EpgSearchIndex._(
      entries,
      List<int>.unmodifiable(genres.toList()..sort()),
    );
  }

  const EpgSearchIndex._(this._entries, this.genreValues);

  final List<_IndexedEvent> _entries;

  /// The genre level-1 values present in the dataset,
  /// ascending (see [epgSearchGenreValues]).
  final List<int> genreValues;

  /// The number of events in the dataset.
  int get eventCount => _entries.length;

  /// The events matching [query] and, when given,
  /// [genreLevel1], in start order (see [searchEpgProgrammes]
  /// for the matching rules).
  List<EpgSearchHit> search({String query = '', int? genreLevel1}) {
    final needle = query.trim().toLowerCase();
    return [
      for (final entry in _entries)
        if ((genreLevel1 == null || entry.event.genreLevel1 == genreLevel1) &&
            (needle.isEmpty || entry.searchText.contains(needle)))
          EpgSearchHit(service: entry.service, event: entry.event),
    ];
  }

  static String _searchTextOf(EpgEvent event, String channelName) {
    final fields = [
      event.title,
      event.shortText,
      event.description,
      event.cast,
      channelName,
    ];
    return [
      for (final field in fields)
        if (field != null) field.toLowerCase(),
    ].join('\n');
  }
}

class _IndexedEvent {
  const _IndexedEvent({
    required this.service,
    required this.event,
    required this.searchText,
  });

  final EpgServiceGuide service;
  final EpgEvent event;

  /// The event's searchable fields, lowercased once and
  /// joined with newlines (see [EpgSearchIndex]).
  final String searchText;
}
