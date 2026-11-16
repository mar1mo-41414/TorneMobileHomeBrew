/// Recorded titles screen (plan 5.6 item 3): the title list with
/// remaining copy counts and protection state, and a detail view
/// with the additional information. Playback goes through the
/// PlaybackEngine boundary only; the v1 stub reports "unsupported"
/// and the UI turns that into the not-implemented notice
/// (plan 1.2 item 5, 5.7).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'format.dart';
import 'schedules_screen.dart' show twoPaneBreakpoint;
import 'widgets.dart';

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
          ? const Center(child: Text('nasne が登録されていません。設定画面で登録してください。'))
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

class _TitleList extends ConsumerWidget {
  const _TitleList({
    required this.reg,
    required this.selectedId,
    required this.onSelect,
  });

  final RegisteredNasne reg;
  final String? selectedId;
  final void Function(RecordedTitle title, bool twoPane) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(titlesProvider(reg));
    final counts = ref.watch(titleCountsProvider(reg)).value;
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
        Expanded(
          child: asyncSection(titles, (list) {
            if (list.isEmpty) {
              return const Center(child: Text('録画済みのタイトルはありません'));
            }
            final listView = ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final t = list[i];
                return ListTile(
                  selected: t.id == selectedId,
                  leading: Icon(
                    t.recordingFlag
                        ? Icons.fiber_manual_record
                        : Icons.movie_outlined,
                    color: t.recordingFlag
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
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
                  onTap: () => onSelect(
                    t,
                    MediaQuery.sizeOf(context).width >= twoPaneBreakpoint,
                  ),
                );
              },
            );
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < twoPaneBreakpoint) {
                  return listView;
                }
                RecordedTitle? selected;
                for (final t in list) {
                  if (t.id == selectedId) selected = t;
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
          if (t.id == titleId) return TitleDetailView(reg: reg, title: t);
        }
        return const Center(child: Text('タイトルが見つかりません'));
      }, onRetry: () => ref.invalidate(titlesProvider(reg))),
    );
  }
}

/// The title detail: merged XSRS + DIDL information and the playback
/// action (which surfaces the v1 not-implemented notice).
class TitleDetailView extends ConsumerWidget {
  const TitleDetailView({super.key, required this.reg, required this.title});

  final RegisteredNasne reg;
  final RecordedTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = title;
    final channels = ref.watch(channelsProvider(reg)).value;
    final sizeBytes = t.res
        .map((r) => r.cleartextSize)
        .whereType<int>()
        .firstOrNull;
    final qualities = [
      for (final r in t.res)
        if (r.quality != null) r.quality!,
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
        if (t.desiredQualityMode != null)
          FieldRow(label: '画質モード', value: '${t.desiredQualityMode}'),
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
        FilledButton.icon(
          onPressed: () => _play(context, ref),
          icon: const Icon(Icons.play_arrow),
          label: const Text('再生'),
        ),
        const SizedBox(height: 8),
        const Text('再生は v1 では未実装です (下のボタンを押すと案内が表示されます)。'),
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final engine = ref.read(deviceServicesProvider(reg)).playback;
    if (!engine.isSupported || title.res.isEmpty) {
      await _showPlaybackNotice(context);
      return;
    }
    try {
      await engine.startPlayback(title, title.res.first);
    } on NasneError catch (e) {
      if (!context.mounted) return;
      if (e.category == NasneErrorCategory.unsupported) {
        await _showPlaybackNotice(context);
      } else {
        showSnack(context, '再生を開始できませんでした');
      }
    }
  }

  Future<void> _showPlaybackNotice(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('再生は未実装です'),
        content: const Text(
          '録画の再生には DTCP-IP の資格情報 (DTLA 署名の証明書と機器秘密鍵のペア) '
          'が必要です。資格情報ペアが得られていないため、v1 では再生は未実装です。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}
