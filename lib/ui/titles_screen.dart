/// Recorded titles screen (plan 5.6 item 3): the title list with
/// remaining copy counts and protection state, and a detail view
/// with the additional information. Playback goes through the
/// PlaybackEngine boundary only; the v1 stub reports "unsupported"
/// and the UI turns that into the not-implemented notice
/// (plan 1.2 item 5, 5.7).
///
/// Plan 86: when the nasne holds a resume position for a title,
/// the detail view asks whether to continue from it or start at
/// the beginning, and the choice reaches the player as its open
/// start. Before this the position was display-only (plan 85
/// item 1).
///
/// Plan 86.6: list rows and the detail view show the title's
/// thumbnail (recorded/thumbnailMapGet, extracted defensively
/// by magic bytes) when the unit provides one. Before this the
/// endpoint was defined but never called (plan 85 item 6).
///
/// Plan 86.5: the list can be searched by title, sorted, and
/// filtered by channel / genre / unwatched; the genre comes
/// from the DIDL merge (upnp:genre). Before this the list was
/// the raw fetch order only (plan 85 item 5).
///
/// Plan 86.3: titles can be deleted from the detail view (and
/// by long-pressing a list row), behind a confirmation.
/// Protected and currently-recording titles are refused with
/// the reason, before any confirmation. Before this the app
/// had no title deletion at all (plan 85 item 3).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'error_messages.dart';
import 'format.dart';
import 'playback_launcher.dart';
import 'player_screen.dart';
import 'title_list_filter.dart';
import 'schedules_screen.dart' show twoPaneBreakpoint;
import 'widgets.dart';

/// The resume start a title offers (plan 86): the position the
/// nasne recorded, as a duration, or null when there is nothing
/// to resume from (never played, or playback reached the start).
Duration? resumeStartOf(RecordedTitle title) {
  final seconds = title.resumePointSeconds;
  if (seconds == null || seconds <= 0) return null;
  return Duration(seconds: seconds);
}

/// Asks whether to continue from [resumeStart] or start over
/// (plan 86). Returns true for "continue", false for "from the
/// beginning", and null when the dialog was dismissed without a
/// choice (the caller then does not start playback).
Future<bool?> showResumeChoiceDialog(
  BuildContext context,
  Duration resumeStart,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('前回の続きがあります'),
      content: Text(
        '前回は ${formatDurationSeconds(resumeStart.inSeconds)} まで観ました。'
        '続きから再生しますか？',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('最初から再生'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('続きから再生'),
        ),
      ],
    ),
  );
}

/// The title deletion flow (plan 86.3), shared by the detail
/// view's delete button and the list's long-press. Protected
/// titles (the unit's guard against accidental deletion) and
/// titles still being recorded are refused with the reason and
/// never reach the confirmation. Anything else asks first —
/// deletion cannot be undone — then deletes, refreshes the
/// list and counts, and reports. [onDeleted] runs after a
/// successful deletion (the detail page uses it to go back to
/// the list; the two-pane layout needs nothing, its selection
/// simply stops resolving).
Future<void> deleteRecordedTitle({
  required BuildContext context,
  required WidgetRef ref,
  required RegisteredNasne reg,
  required RecordedTitle title,
  VoidCallback? onDeleted,
}) async {
  if (title.protectFlag) {
    await _showDeleteRefusal(context, 'このタイトルは保護されているため削除できません。');
    return;
  }
  if (title.recordingFlag) {
    await _showDeleteRefusal(context, '録画中のタイトルは削除できません。');
    return;
  }
  final confirmed = await confirmDialog(
    context,
    title: 'タイトルを削除',
    message: '「${title.title}」を削除しますか？\n削除した録画は元に戻せません。',
    confirmLabel: '削除',
  );
  if (!confirmed || !context.mounted) return;
  try {
    await ref.read(deviceServicesProvider(reg)).titles.deleteTitle(title.id);
  } on NasneError catch (e) {
    ref.read(diagLogProvider)(DiagCategory.ui, 'title delete failed: $e');
    if (context.mounted) showSnack(context, userMessageForError(e));
    return;
  } catch (e) {
    ref.read(diagLogProvider)(DiagCategory.ui, 'title delete failed: $e');
    if (context.mounted) showSnack(context, '削除できませんでした');
    return;
  }
  ref.invalidate(titlesProvider(reg));
  ref.invalidate(titleCountsProvider(reg));
  if (!context.mounted) return;
  showSnack(context, '削除しました');
  onDeleted?.call();
}

Future<void> _showDeleteRefusal(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('削除できません'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

class TitlesScreen extends ConsumerStatefulWidget {
  const TitlesScreen({super.key});

  @override
  ConsumerState<TitlesScreen> createState() => _TitlesScreenState();
}

class _TitlesScreenState extends ConsumerState<TitlesScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('録画済み'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () {
                ref.invalidate(titlesProvider(reg));
                ref.invalidate(titleCountsProvider(reg));
              },
            ),
        ],
      ),
      body: reg == null
          ? NoDeviceView(
              onRegister: () =>
                  ref.read(tabIndexProvider.notifier).select(AppTabs.settings),
            )
          : _TitleList(
              reg: reg,
              selectedId: _selectedId,
              onSelect: (title, twoPane) {
                if (twoPane) {
                  setState(() => _selectedId = title.id);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TitleDetailPage(reg: reg, titleId: title.id),
                    ),
                  );
                }
              },
            ),
    );
  }
}

class _TitleList extends ConsumerStatefulWidget {
  const _TitleList({
    required this.reg,
    required this.selectedId,
    required this.onSelect,
  });

  final RegisteredNasne reg;
  final String? selectedId;
  final void Function(RecordedTitle title, bool twoPane) onSelect;

  @override
  ConsumerState<_TitleList> createState() => _TitleListState();
}

class _TitleListState extends ConsumerState<_TitleList> {
  final _searchController = TextEditingController();
  String _query = '';
  TitleSortOrder _sort = TitleSortOrder.recordedNewest;
  String? _channelKey;
  String? _genre;
  bool _unwatchedOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _channelKey = null;
      _genre = null;
      _unwatchedOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.reg;
    final titles = ref.watch(titlesProvider(reg));
    final counts = ref.watch(titleCountsProvider(reg)).value;
    final allTitles = titles.value ?? const <RecordedTitle>[];
    final channelChoices = titleChannelChoices(allTitles);
    final genreChoices = titleGenreChoices(allTitles);
    // A chosen value can vanish when the list refreshes (its
    // last title was deleted, say); fall back to "all" instead
    // of filtering everything out behind the user's back.
    final channelKey =
        _channelKey != null && channelChoices.contains(_channelKey)
        ? _channelKey
        : null;
    final genre = _genre != null && genreChoices.contains(_genre)
        ? _genre
        : null;
    final filter = TitleListFilter(
      query: _query,
      channelKey: channelKey,
      genre: genre,
      unwatchedOnly: _unwatchedOnly,
    );
    final filteredCount = filter.isActive
        ? applyTitleListView(allTitles, filter: filter, sort: _sort).length
        : null;
    return Column(
      children: [
        if (counts != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('全 ${counts.count} 件 (上限 ${counts.max} 件)'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'タイトルで検索',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '検索をクリア',
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _query = '';
                      }),
                    ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<TitleSortOrder>(
                  value: _sort,
                  items: [
                    for (final order in TitleSortOrder.values)
                      DropdownMenuItem(value: order, child: Text(order.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                ),
                DropdownButton<String?>(
                  value: channelKey,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全チャンネル')),
                    for (final choice in channelChoices)
                      DropdownMenuItem(value: choice, child: Text(choice)),
                  ],
                  onChanged: (value) => setState(() => _channelKey = value),
                ),
                DropdownButton<String?>(
                  value: genre,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('全ジャンル')),
                    for (final choice in genreChoices)
                      DropdownMenuItem(value: choice, child: Text(choice)),
                  ],
                  onChanged: (value) => setState(() => _genre = value),
                ),
                FilterChip(
                  label: const Text('未視聴のみ'),
                  selected: _unwatchedOnly,
                  onSelected: (value) => setState(() => _unwatchedOnly = value),
                ),
                if (filter.isActive) ...[
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('条件をクリア'),
                  ),
                  if (filteredCount != null) Text('条件に合うのは $filteredCount 件'),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: asyncSection(titles, (list) {
            if (list.isEmpty) {
              return const Center(child: Text('録画済みのタイトルはありません'));
            }
            final view = applyTitleListView(list, filter: filter, sort: _sort);
            if (view.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('条件に合うタイトルがありません'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _clearFilters,
                      child: const Text('条件をクリア'),
                    ),
                  ],
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                // The tap behaviour and the pane layout must agree
                // on what "wide" means, so both read the same
                // width: the one this list actually gets. The tap
                // once read the MediaQuery window width while the
                // layout read these constraints, which the shell's
                // navigation rail narrows; in the band between the
                // two (a 1024-wide iPad in landscape, a Split View
                // or Stage Manager window) a tap only updated the
                // selection state — no detail page was pushed and
                // no detail pane existed to show it — so selecting
                // a title appeared to do nothing at all.
                final twoPane = constraints.maxWidth >= twoPaneBreakpoint;
                final listView = ListView.builder(
                  itemCount: view.length,
                  itemBuilder: (context, i) {
                    final t = view[i];
                    return ListTile(
                      selected: t.id == widget.selectedId,
                      leading: _TitleLeading(reg: reg, title: t),
                      title: Text(t.title),
                      subtitle: Text(
                        '${t.scheduledStart != null ? formatDateTimeJst(t.scheduledStart!) : ''}'
                        '${t.scheduledDurationSeconds != null ? ' (${formatDurationSeconds(t.scheduledDurationSeconds!)})' : ''}'
                        '${t.channelName != null ? ' ${t.channelName}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (t.protectFlag) const Icon(Icons.lock, size: 16),
                          if (t.newFlag)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.fiber_new, size: 18),
                            ),
                          if (t.copyCountRemaining != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text('残り ${t.copyCountRemaining} 回'),
                            ),
                        ],
                      ),
                      onTap: () => widget.onSelect(t, twoPane),
                      onLongPress: () => deleteRecordedTitle(
                        context: context,
                        ref: ref,
                        reg: reg,
                        title: t,
                      ),
                    );
                  },
                );
                if (!twoPane) return listView;
                RecordedTitle? selected;
                for (final t in view) {
                  if (t.id == widget.selectedId) selected = t;
                }
                return Row(
                  children: [
                    Expanded(flex: 5, child: listView),
                    const VerticalDivider(thickness: 1, width: 1),
                    Expanded(
                      flex: 6,
                      child: selected == null
                          ? const Center(child: Text('タイトルを選択してください'))
                          : TitleDetailView(reg: reg, title: selected),
                    ),
                  ],
                );
              },
            );
          }, onRetry: () => ref.invalidate(titlesProvider(reg))),
        ),
      ],
    );
  }
}

/// A title's leading visual (plan 86.6): the thumbnail when the
/// unit provides one, else the movie icon. A title still being
/// recorded keeps the red recording icon — its state matters
/// more than a picture, and its thumbnail may not exist yet.
class _TitleLeading extends ConsumerWidget {
  const _TitleLeading({required this.reg, required this.title});

  final RegisteredNasne reg;
  final RecordedTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Icon(
      title.recordingFlag ? Icons.fiber_manual_record : Icons.movie_outlined,
      color: title.recordingFlag ? Theme.of(context).colorScheme.error : null,
    );
    if (title.recordingFlag) return fallback;
    final bytes = ref
        .watch(titleThumbnailProvider((reg: reg, titleId: title.id)))
        .value;
    if (bytes == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.memory(
        bytes,
        width: 64,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// The detail view's thumbnail banner (plan 86.6): a 16:9
/// picture above the title when the unit provides one, and
/// nothing at all when it does not (no empty box).
class _TitleThumbnailBanner extends ConsumerWidget {
  const _TitleThumbnailBanner({required this.reg, required this.titleId});

  final RegisteredNasne reg;
  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref
        .watch(titleThumbnailProvider((reg: reg, titleId: titleId)))
        .value;
    if (bytes == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Detail page for narrow layouts.
class TitleDetailPage extends ConsumerWidget {
  const TitleDetailPage({super.key, required this.reg, required this.titleId});

  final RegisteredNasne reg;
  final String titleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(titlesProvider(reg));
    return Scaffold(
      appBar: AppBar(title: const Text('タイトルの詳細')),
      body: asyncSection(titles, (list) {
        for (final t in list) {
          if (t.id == titleId) {
            return TitleDetailView(
              reg: reg,
              title: t,
              onDeleted: () => Navigator.of(context).pop(),
            );
          }
        }
        return const Center(child: Text('タイトルが見つかりません'));
      }, onRetry: () => ref.invalidate(titlesProvider(reg))),
    );
  }
}

/// The title detail: merged XSRS + DIDL information and the playback
/// action. When the title carries a mobile resource alongside the
/// original, a playback quality choice is offered (plan 33); the
/// default is always the original quality.
class TitleDetailView extends ConsumerStatefulWidget {
  const TitleDetailView({
    super.key,
    required this.reg,
    required this.title,
    this.onDeleted,
  });

  final RegisteredNasne reg;
  final RecordedTitle title;

  /// Runs after this title was deleted from the detail view
  /// (plan 86.3): the pushed detail page goes back to the list.
  /// Null in the two-pane layout, where the refreshed list
  /// simply stops resolving the selection.
  final VoidCallback? onDeleted;

  @override
  ConsumerState<TitleDetailView> createState() => _TitleDetailViewState();
}

class _TitleDetailViewState extends ConsumerState<TitleDetailView> {
  /// Playback quality choice (plan 33): false = the title's
  /// original resource (DR / 3倍), true = the mobile transcode.
  /// A per-playback option only — nothing is persisted, and every
  /// visit to this screen starts on the original.
  bool _useMobile = false;

  /// A playback start is in flight (plan 35). Starting takes a
  /// second or more (credentials -> HEAD -> AKE -> proxy); the
  /// build-13 field log showed a second tap in that window
  /// starting a whole second session, whose player screen then
  /// shared — and dropped — the first one's wakelock. While a
  /// start is in flight the button is disabled and _play is
  /// re-entrancy-guarded.
  bool _starting = false;

  RegisteredNasne get reg => widget.reg;
  RecordedTitle get title => widget.title;

  @override
  Widget build(BuildContext context) {
    final t = title;
    final channels = ref.watch(channelsProvider(reg)).value;
    final credentialSummary = ref.watch(credentialSummaryProvider);
    final credentialsMissing =
        credentialSummary.hasValue && credentialSummary.value == null;
    final sizeBytes = t.res
        .map((r) => r.cleartextSize)
        .whereType<int>()
        .firstOrNull;
    final qualities = [
      for (final r in t.res)
        if (r.quality != null) r.quality!,
    ];
    final originalRes = t.originalRes;
    final mobileRes = t.mobileRes;
    final originalLabel = originalRes?.quality == null
        ? '元画質'
        : '元画質 (${resQualityLabel(originalRes!.quality)})';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!t.recordingFlag) _TitleThumbnailBanner(reg: reg, titleId: t.id),
        Text(t.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (t.scheduledStart != null)
          FieldRow(
            label: '録画日時',
            value: formatDateTimeWithWeekdayJst(t.scheduledStart!),
          ),
        if (t.scheduledDurationSeconds != null)
          FieldRow(
            label: '長さ',
            value: formatDurationSeconds(t.scheduledDurationSeconds!),
          ),
        FieldRow(
          label: 'チャンネル',
          value: t.channelName ?? channelDisplayName(channels, t.channel),
        ),
        if (t.genre != null && t.genre!.isNotEmpty)
          FieldRow(label: 'ジャンル', value: t.genre!),
        if (t.desiredQualityMode != null)
          FieldRow(
            label: '画質モード',
            value: qualityModeLabel(t.desiredQualityMode!),
          ),
        if (t.copyCountRemaining != null)
          FieldRow(label: '残コピー回数', value: '${t.copyCountRemaining} 回'),
        FieldRow(label: '保護', value: t.protectFlag ? '保護あり' : 'なし'),
        if (t.recordingFlag) const FieldRow(label: '状態', value: '録画中'),
        if (sizeBytes != null)
          FieldRow(label: 'サイズ', value: formatBytes(sizeBytes)),
        if (t.resumePointSeconds != null && t.resumePointSeconds! > 0)
          FieldRow(
            label: '再開位置',
            value: formatDurationSeconds(t.resumePointSeconds!),
          ),
        if (qualities.isNotEmpty)
          FieldRow(label: 'res 品質', value: qualities.join(', ')),
        if (t.description != null && t.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('概要', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(t.description!),
        ],
        if (t.longDescription != null && t.longDescription!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('詳細', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(t.longDescription!),
        ],
        const SizedBox(height: 24),
        if (mobileRes != null) ...[
          Text('再生画質', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(originalLabel)),
              const ButtonSegment(value: true, label: Text('モバイル')),
            ],
            selected: {_useMobile},
            onSelectionChanged: (selection) =>
                setState(() => _useMobile = selection.first),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _starting ? null : () => _play(context, ref),
          icon: const Icon(Icons.play_arrow),
          label: const Text('再生'),
        ),
        // The credential note shows only while no pair is
        // imported (plan 86.2): as a permanent fixture it told
        // people who had already imported that they still had
        // something to do. While the state is loading nothing
        // is shown, so the text never flickers in and out.
        if (credentialsMissing) ...[
          const SizedBox(height: 8),
          const Text('録画の再生には資格情報のインポートが必要です。'),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => deleteRecordedTitle(
            context: context,
            ref: ref,
            reg: reg,
            title: title,
            onDeleted: widget.onDeleted,
          ),
          icon: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          label: Text(
            'このタイトルを削除',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    if (_starting) return;
    final engine = ref.read(deviceServicesProvider(reg)).playback;
    if (!engine.isSupported) {
      await showPlaybackUnsupportedDialog(context, subject: '録画の再生');
      return;
    }
    if (title.res.isEmpty) {
      showSnack(context, '再生可能なコンテンツがありません');
      return;
    }
    final res =
        (_useMobile ? title.mobileRes : title.originalRes) ?? title.res.first;
    // Resume (plan 86): a title the viewer stopped midway offers
    // its recorded position. Ask before starting — beginning a
    // session is the expensive step, and the choice belongs
    // before it, not after.
    var initialStart = resumeStartOf(title);
    if (initialStart != null) {
      final resume = await showResumeChoiceDialog(context, initialStart);
      if (!context.mounted) return;
      if (resume == null) return;
      if (!resume) initialStart = null;
    }
    setState(() => _starting = true);
    try {
      await startPlaybackAndShowPlayer(
        context: context,
        ref: ref,
        start: () => engine.startPlayback(title, res),
        buildPlayer: (session) => PlayerScreen(
          title: title.title,
          session: session,
          initialStart: initialStart,
        ),
        unsupportedSubject: '録画の再生',
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}
