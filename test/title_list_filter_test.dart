/// Plan 86.5 (#5): pure search / sort / filter logic for the
/// recorded title list.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/models/schedule.dart';
import 'package:tmhb/core/models/title.dart';
import 'package:tmhb/ui/title_list_filter.dart';

RecordedTitle _t(
  String id,
  String title, {
  String? start,
  String? channelName,
  String? genre,
  bool newFlag = false,
  ScheduleChannel? channel,
}) {
  return RecordedTitle(
    id: id,
    title: title,
    scheduledStart: start == null ? null : DateTime.parse(start),
    channelName: channelName,
    genre: genre,
    newFlag: newFlag,
    channel: channel,
  );
}

final _items = [
  _t(
    '1',
    'ニュース朝',
    start: '2026-11-15T07:00:00+09:00',
    channelName: 'A放送',
    genre: 'ニュース／報道',
  ),
  _t(
    '2',
    'アニメ夜',
    start: '2026-11-15T23:00:00+09:00',
    channelName: 'B放送',
    genre: 'アニメ／特撮',
    newFlag: true,
  ),
  _t(
    '3',
    'ニュース夜',
    start: '2026-11-14T23:00:00+09:00',
    channelName: 'A放送',
    genre: 'ニュース／報道',
    newFlag: true,
  ),
  _t('4', '日時なしアニメ', genre: 'アニメ／特撮'),
];

List<String> _ids(List<RecordedTitle> titles) => [for (final t in titles) t.id];

void main() {
  group('applyTitleListView filtering', () {
    test('query matches a title substring, case-insensitively', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(query: 'ニュース'),
        sort: TitleSortOrder.recordedNewest,
      );
      expect(_ids(view), ['1', '3']);
    });

    test('channel filter uses the DIDL channel name', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(channelKey: 'B放送'),
        sort: TitleSortOrder.recordedNewest,
      );
      expect(_ids(view), ['2']);
    });

    test('genre filter matches the merged DIDL genre', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(genre: 'アニメ／特撮'),
        sort: TitleSortOrder.titleAsc,
      );
      expect(_ids(view), ['2', '4']);
    });

    test('unwatchedOnly keeps only new-flagged titles', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(unwatchedOnly: true),
        sort: TitleSortOrder.recordedNewest,
      );
      expect(_ids(view), ['2', '3']);
    });

    test('conditions combine', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(query: 'ニュース', unwatchedOnly: true),
        sort: TitleSortOrder.recordedNewest,
      );
      expect(_ids(view), ['3']);
    });
  });

  group('applyTitleListView sorting', () {
    test('newest first, undated last', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(),
        sort: TitleSortOrder.recordedNewest,
      );
      expect(_ids(view), ['2', '1', '3', '4']);
    });

    test('oldest first, undated last', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(),
        sort: TitleSortOrder.recordedOldest,
      );
      expect(_ids(view), ['3', '1', '2', '4']);
    });

    test('title order', () {
      final view = applyTitleListView(
        _items,
        filter: const TitleListFilter(),
        sort: TitleSortOrder.titleAsc,
      );
      expect(_ids(view), ['2', '3', '1', '4']);
    });

    test('the input list is not modified', () {
      final input = List.of(_items);
      applyTitleListView(
        input,
        filter: const TitleListFilter(),
        sort: TitleSortOrder.titleAsc,
      );
      expect(_ids(input), ['1', '2', '3', '4']);
    });
  });

  group('choices and keys', () {
    test('channel choices are distinct and sorted', () {
      expect(titleChannelChoices(_items), ['A放送', 'B放送']);
    });

    test('genre choices are distinct and sorted', () {
      expect(titleGenreChoices(_items), ['アニメ／特撮', 'ニュース／報道']);
    });

    test('channel key falls back to the XSRS service form', () {
      const channel = ScheduleChannel(
        broadcastingType: 2,
        channelType: 2,
        serviceId: 0xDE00,
      );
      final title = _t('9', 'x', channel: channel);
      expect(titleChannelKey(title), 'サービス ${channel.serviceIdHex}');
    });

    test('a filter with a query of blanks is not active', () {
      expect(const TitleListFilter(query: '  ').isActive, isFalse);
      expect(const TitleListFilter(unwatchedOnly: true).isActive, isTrue);
    });
  });
}
