/// Programme search screen (plan 86, plan 85 item 8):
/// keyword and genre search over the EPG dataset the guide
/// providers already hold. Each hit leads to the same event
/// detail dialog — and from there the same reservation
/// form — as a tap on the guide grid (see
/// [showEpgEventDetail]).
///
/// Both bands are searched together: the viewer thinks in
/// programmes, not in broadcasting types, and the
/// terrestrial / BS split is a guide-grid concern. A band
/// whose guide is still loading or failed to load simply
/// contributes nothing yet; the other band's hits are
/// shown. The search runs over the full dataset, including
/// subchannels the guide grid may be set to hide — finding
/// a programme is the point of searching for it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/bs_epg_providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'epg_screen.dart';
import 'epg_search.dart';
import 'format.dart';
import 'live_screen.dart';
import 'widgets.dart';

class EpgSearchScreen extends ConsumerStatefulWidget {
  const EpgSearchScreen({super.key, required this.reg});

  final RegisteredNasne reg;

  @override
  ConsumerState<EpgSearchScreen> createState() => _EpgSearchScreenState();
}

class _EpgSearchScreenState extends ConsumerState<EpgSearchScreen> {
  final _queryController = TextEditingController();
  String _query = '';
  int? _genreLevel1;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terrestrial = ref.watch(epgGuideProvider(widget.reg)).value;
    final bs = ref.watch(bsEpgGuideProvider(widget.reg)).value;
    final guides = <EpgGuide>[?terrestrial, ?bs];
    final genreValues = epgSearchGenreValues(guides);
    // A genre picked before the data (re)loaded may not
    // exist in the current dataset; fall back to "all"
    // rather than filtering everything away behind the
    // viewer's back.
    final genre = genreValues.contains(_genreLevel1) ? _genreLevel1 : null;
    final searched = _query.trim().isNotEmpty || genre != null;
    final hits = searched
        ? searchEpgProgrammes(
            guides: guides,
            query: _query,
            genreLevel1: genre,
          )
        : const <EpgSearchHit>[];

    return Scaffold(
      appBar: AppBar(title: const Text('番組検索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'キーワード',
                hintText: '番組名・内容・出演者など',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: 'クリア',
                        onPressed: () {
                          _queryController.clear();
                          setState(() => _query = '');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Text('ジャンル'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<int?>(
                    value: genre,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('すべて'),
                      ),
                      for (final value in genreValues)
                        DropdownMenuItem<int?>(
                          value: value,
                          child: Text(epgSearchGenreLabel(value)),
                        ),
                    ],
                    onChanged: (value) => setState(() => _genreLevel1 = value),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResults(guides, searched, hits)),
        ],
      ),
    );
  }

  Widget _buildResults(
    List<EpgGuide> guides,
    bool searched,
    List<EpgSearchHit> hits,
  ) {
    if (guides.isEmpty) return const LoadingView();
    if (!searched) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'キーワードを入力するか、ジャンルを選ぶと、'
            '番組表から番組を探せます。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (hits.isEmpty) {
      return const Center(child: Text('見つかりませんでした。'));
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        final event = hit.event;
        return ListTile(
          title: Text(event.title ?? '番組情報なし'),
          subtitle: Text(
            '${hit.channelName}\n'
            '${formatDateTimeWithWeekdayJst(event.start)} 〜 '
            '${formatTimeJst(event.end)}',
          ),
          isThreeLine: true,
          onTap: () => showEpgEventDetail(
            context,
            reg: widget.reg,
            channel: hit.channel,
            channelName: hit.channelName,
            event: event,
            onWatch: () => openLiveChannelForEpg(
              context,
              ref,
              reg: widget.reg,
              channel: hit.channel,
            ),
          ),
        );
      },
    );
  }
}
