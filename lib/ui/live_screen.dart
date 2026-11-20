/// Live viewing screen (plan 39): the LiveTuner bands and their
/// channels, each with the programme currently on air, and a
/// detail view that starts viewing through the PlaybackEngine
/// boundary — the same DTCP-IP path as recorded playback, with
/// the plan-33 quality choice. The official torne name of the
/// feature, TV視聴, is the screen's title.
///
/// The programme information is the snapshot the DIDL items
/// carried when the list was fetched; the refresh action
/// re-fetches it (a programme boundary does not update an
/// already listed item).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'format.dart';
import 'playback_launcher.dart';
import 'player_screen.dart';
import 'schedules_screen.dart' show twoPaneBreakpoint;
import 'widgets.dart';

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TV視聴'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () => ref.invalidate(liveChannelsProvider(reg)),
            ),
        ],
      ),
      body: reg == null
          ? NoDeviceView(
              onRegister: () =>
                  ref.read(tabIndexProvider.notifier).select(AppTabs.settings),
            )
          : _LiveList(
              reg: reg,
              selectedId: _selectedId,
              onSelect: (channel, twoPane) {
                if (twoPane) {
                  setState(() => _selectedId = channel.id);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LiveChannelDetailPage(
                        reg: reg,
                        channelId: channel.id,
                      ),
                    ),
                  );
                }
              },
            ),
    );
  }
}

class _LiveList extends ConsumerWidget {
  const _LiveList({
    required this.reg,
    required this.selectedId,
    required this.onSelect,
  });

  final RegisteredNasne reg;
  final String? selectedId;
  final void Function(LiveChannel channel, bool twoPane) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(liveChannelsProvider(reg));
    return asyncSection(bands, (list) {
      final channels = [for (final band in list) ...band.channels];
      if (channels.isEmpty) {
        return const Center(child: Text('視聴可能なチャンネルがありません'));
      }
      final listView = ListView(
        children: [
          for (final band in list)
            if (band.channels.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  band.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              for (final channel in band.channels)
                ListTile(
                  selected: channel.id == selectedId,
                  leading: const Icon(Icons.live_tv_outlined),
                  title: Text(channel.channelName ?? channel.programTitle),
                  subtitle: Text(
                    _channelSubtitle(channel),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onSelect(
                    channel,
                    MediaQuery.sizeOf(context).width >= twoPaneBreakpoint,
                  ),
                ),
            ],
        ],
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < twoPaneBreakpoint) return listView;
          LiveChannel? selected;
          for (final channel in channels) {
            if (channel.id == selectedId) selected = channel;
          }
          return Row(
            children: [
              Expanded(flex: 5, child: listView),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                flex: 6,
                child: selected == null
                    ? const Center(child: Text('チャンネルを選択してください'))
                    : LiveChannelDetailView(reg: reg, channel: selected),
              ),
            ],
          );
        },
      );
    }, onRetry: () => ref.invalidate(liveChannelsProvider(reg)));
  }
}

/// The list subtitle: the on-air time range and programme title
/// (the channel name already heads the tile), or the programme
/// outline when the item carried no channel name.
String _channelSubtitle(LiveChannel channel) {
  final start = channel.programStart;
  final end = channel.programEnd;
  final range = start != null && end != null
      ? '${formatTimeJst(start)}–${formatTimeJst(end)} '
      : '';
  if (channel.channelName != null) return '$range${channel.programTitle}';
  return '$range${channel.description ?? ''}';
}

/// Detail page for narrow layouts.
class LiveChannelDetailPage extends ConsumerWidget {
  const LiveChannelDetailPage({
    super.key,
    required this.reg,
    required this.channelId,
  });

  final RegisteredNasne reg;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bands = ref.watch(liveChannelsProvider(reg));
    return Scaffold(
      appBar: AppBar(title: const Text('チャンネルの詳細')),
      body: asyncSection(bands, (list) {
        for (final band in list) {
          for (final channel in band.channels) {
            if (channel.id == channelId) {
              return LiveChannelDetailView(reg: reg, channel: channel);
            }
          }
        }
        return const Center(child: Text('チャンネルが見つかりません'));
      }, onRetry: () => ref.invalidate(liveChannelsProvider(reg))),
    );
  }
}

/// The channel detail: the current programme's information and
/// the viewing action, with the plan-33 quality choice when the
/// channel offers a mobile resource. The default is always the
/// original quality; the choice is per viewing, never persisted.
class LiveChannelDetailView extends ConsumerStatefulWidget {
  const LiveChannelDetailView({
    super.key,
    required this.reg,
    required this.channel,
  });

  final RegisteredNasne reg;
  final LiveChannel channel;

  @override
  ConsumerState<LiveChannelDetailView> createState() =>
      _LiveChannelDetailViewState();
}

class _LiveChannelDetailViewState extends ConsumerState<LiveChannelDetailView> {
  /// Playback quality choice (plan 33, shared with recordings).
  bool _useMobile = false;

  /// A viewing start is in flight (plan 35 guard, shared with
  /// recordings): while set, the button is disabled and _watch
  /// is re-entrancy-guarded.
  bool _starting = false;

  RegisteredNasne get reg => widget.reg;
  LiveChannel get channel => widget.channel;

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    final originalRes = ch.originalRes;
    final mobileRes = ch.mobileRes;
    final originalLabel = originalRes?.quality == null
        ? '元画質'
        : '元画質 (${resQualityLabel(originalRes!.quality)})';
    final start = ch.programStart;
    final end = ch.programEnd;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(ch.programTitle, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (ch.channelName != null)
          FieldRow(label: 'チャンネル', value: ch.channelName!),
        if (start != null && end != null)
          FieldRow(
            label: '放送時間',
            value:
                '${formatDateTimeWithWeekdayJst(start)}–${formatTimeJst(end)}',
          ),
        if (ch.genre != null) FieldRow(label: 'ジャンル', value: ch.genre!),
        if (ch.description != null && ch.description!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('概要', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(ch.description!),
        ],
        if (ch.longDescription != null && ch.longDescription!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('詳細', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(ch.longDescription!),
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
          onPressed: _starting ? null : () => _watch(context, ref),
          icon: const Icon(Icons.play_arrow),
          label: const Text('視聴'),
        ),
        const SizedBox(height: 8),
        const Text('視聴には DTCP-IP の資格情報が必要です (設定画面からインポートできます)。'),
      ],
    );
  }

  Future<void> _watch(BuildContext context, WidgetRef ref) async {
    if (_starting) return;
    final engine = ref.read(deviceServicesProvider(reg)).playback;
    if (!engine.isSupported) {
      await showPlaybackUnsupportedDialog(context, subject: 'TV視聴');
      return;
    }
    if (channel.res.isEmpty) {
      showSnack(context, '視聴可能なコンテンツがありません');
      return;
    }
    final res =
        (_useMobile ? channel.mobileRes : channel.originalRes) ??
        channel.res.first;
    setState(() => _starting = true);
    try {
      await startPlaybackAndShowPlayer(
        context: context,
        ref: ref,
        start: () => engine.startLivePlayback(channel, res),
        buildPlayer: (session) => PlayerScreen(
          title: channel.channelName ?? channel.programTitle,
          session: session,
          live: true,
        ),
        unsupportedSubject: 'TV視聴',
        startFailureMessage: '視聴を開始できませんでした',
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }
}
