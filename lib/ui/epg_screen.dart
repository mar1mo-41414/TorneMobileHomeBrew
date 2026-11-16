/// Programme guide screen (plan 21): the channel x time grid for
/// terrestrial broadcasts, in the official torne layout style —
/// channels as columns, time flowing downwards, one day at a time.
/// Data comes from MetadataService.getProgrammeGuide (the EPGGet
/// dataset behind the MetadataService boundary, plan 12.8); the
/// screen only slices and renders it.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/state.dart';
import '../core/core.dart';
import 'error_messages.dart';
import 'format.dart';
import 'widgets.dart';

/// Vertical scale of the grid: pixels per broadcast minute.
const double _pxPerMinute = 2.4;
const double _channelWidth = 172;
const double _rulerWidth = 40;
const double _headerHeight = 54;

/// Scroll physics that always settles with the grid aligned to a
/// channel-column boundary. Without it the horizontal scroll can
/// rest a few pixels into a column, leaving the leftmost visible
/// column clipped by the viewport edge (its start-time labels lose
/// their first glyph, plan 22).
class _ChannelSnapPhysics extends ScrollPhysics {
  const _ChannelSnapPhysics({super.parent});

  @override
  _ChannelSnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _ChannelSnapPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    if (velocity.abs() < tolerance.velocity) {
      // Slow or finished drag: settle to the nearest boundary.
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        (position.pixels / _channelWidth).round() * _channelWidth,
        velocity,
        tolerance: tolerance,
      );
    }
    // Fling: continue to the next boundary in the fling direction.
    final double target = velocity > 0
        ? (position.pixels / _channelWidth).ceil() * _channelWidth
        : (position.pixels / _channelWidth).floor() * _channelWidth;
    if (target == position.pixels) {
      return super.createBallisticSimulation(position, velocity);
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      velocity,
      tolerance: tolerance,
    );
  }
}

class EpgScreen extends ConsumerStatefulWidget {
  const EpgScreen({super.key});

  @override
  ConsumerState<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends ConsumerState<EpgScreen> {
  /// Selected day as a JST calendar date (stored as a UTC-midnight
  /// DateTime of the JST date fields, like format.dart's helpers).
  DateTime? _selectedDay;
  bool _scrolledToNow = false;

  final _rulerController = ScrollController();
  final _bodyController = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _link(_rulerController, _bodyController);
    _link(_bodyController, _rulerController);
  }

  void _link(ScrollController from, ScrollController to) {
    from.addListener(() {
      if (_syncing || !to.hasClients) return;
      _syncing = true;
      if ((to.offset - from.offset).abs() > 0.5) to.jumpTo(from.offset);
      _syncing = false;
    });
  }

  @override
  void dispose() {
    _rulerController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  /// The JST calendar date (as UTC fields) containing [instant].
  static DateTime _jstDateOf(DateTime instant) {
    final jst = instant.toUtc().add(const Duration(hours: 9));
    return DateTime.utc(jst.year, jst.month, jst.day);
  }

  /// The instant a JST calendar date starts.
  static DateTime _jstDayStart(DateTime jstDate) =>
      jstDate.subtract(const Duration(hours: 9));

  @override
  Widget build(BuildContext context) {
    final reg = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('番組表'),
        actions: [
          if (reg != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '更新',
              onPressed: () {
                ref.invalidate(epgGuideProvider(reg));
                ref.invalidate(channelLogosProvider(reg));
              },
            ),
        ],
      ),
      body: reg == null
          ? const Center(
              child: Text('nasne が登録されていません。設定画面で登録してください。'))
          : ref.watch(epgGuideProvider(reg)).when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  message: userMessageForError(e),
                  onRetry: () => ref.invalidate(epgGuideProvider(reg)),
                ),
                data: (guide) => _GuideView(
                  guide: guide,
                  logos: ref.watch(channelLogosProvider(reg)).value ?? const {},
                  selectedDay: _selectedDay,
                  onSelectDay: (day) => setState(() {
                    _selectedDay = day;
                    _scrolledToNow = false;
                  }),
                  rulerController: _rulerController,
                  bodyController: _bodyController,
                  scrolledToNow: _scrolledToNow,
                  onScrolledToNow: () => _scrolledToNow = true,
                ),
              ),
    );
  }
}

class _GuideView extends StatelessWidget {
  const _GuideView({
    required this.guide,
    required this.logos,
    required this.selectedDay,
    required this.onSelectDay,
    required this.rulerController,
    required this.bodyController,
    required this.scrolledToNow,
    required this.onScrolledToNow,
  });

  final EpgGuide guide;
  final Map<int, List<int>> logos;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelectDay;
  final ScrollController rulerController;
  final ScrollController bodyController;
  final bool scrolledToNow;
  final VoidCallback onScrolledToNow;

  @override
  Widget build(BuildContext context) {
    final from = guide.from;
    final to = guide.to;
    if (from == null || to == null || guide.services.isEmpty) {
      return const Center(child: Text('番組データがありません。'));
    }
    final firstDay = _EpgScreenState._jstDateOf(from);
    final lastDay = _EpgScreenState._jstDateOf(
        to.subtract(const Duration(seconds: 1)));
    final days = <DateTime>[
      for (var d = firstDay;
          !d.isAfter(lastDay);
          d = d.add(const Duration(days: 1)))
        d,
    ];
    final today = _EpgScreenState._jstDateOf(DateTime.now());
    final day = selectedDay ?? (days.contains(today) ? today : days.first);
    final dayStart = _EpgScreenState._jstDayStart(day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    // Initial position: one hour before "now" when today is shown.
    if (!scrolledToNow && day == today) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (bodyController.hasClients) {
          final now = DateTime.now();
          final minutes = now.difference(dayStart).inMinutes - 60;
          bodyController.jumpTo(
              math.max(0, minutes * _pxPerMinute).toDouble());
        }
        onScrolledToNow();
      });
    }

    return Column(
      children: [
        _DaySelector(days: days, selected: day, onSelect: onSelectDay),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _rulerWidth,
                child: Column(
                  children: [
                    const SizedBox(height: _headerHeight),
                    Expanded(
                      child: _TimeRuler(controller: rulerController),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const _ChannelSnapPhysics(),
                  child: SizedBox(
                    width: _channelWidth * guide.services.length,
                    child: Column(
                      children: [
                        _ChannelHeader(services: guide.services, logos: logos),
                        Expanded(
                          child: _DayGrid(
                            services: guide.services,
                            dayStart: dayStart,
                            dayEnd: dayEnd,
                            controller: bodyController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<DateTime> days;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = _EpgScreenState._jstDateOf(DateTime.now());
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          for (final day in days)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(day == today
                    ? '今日 ${day.month}/${day.day}'
                    : '${day.month}/${day.day} (${formatWeekdayJst(day.add(const Duration(hours: 9)))})'),
                selected: day == selected,
                onSelected: (_) => onSelect(day),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  const _ChannelHeader({required this.services, required this.logos});

  final List<EpgServiceGuide> services;
  final Map<int, List<int>> logos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: [
          for (final service in services)
            SizedBox(
              width: _channelWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (logos[service.channel.serviceId] != null)
                      SizedBox(
                        height: 24,
                        child: Image.memory(
                          Uint8List.fromList(logos[service.channel.serviceId]!),
                          fit: BoxFit.contain,
                        ),
                      ),
                    Text(
                      service.channel.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeRuler extends StatelessWidget {
  const _TimeRuler({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      controller: controller,
      physics: const NeverScrollableScrollPhysics(),
      child: SizedBox(
        height: 24 * 60 * _pxPerMinute,
        child: Stack(
          children: [
            for (var hour = 0; hour < 24; hour++)
              Positioned(
                top: hour * 60 * _pxPerMinute + 2,
                left: 0,
                right: 0,
                child: Text(
                  '$hour',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.services,
    required this.dayStart,
    required this.dayEnd,
    required this.controller,
  });

  final List<EpgServiceGuide> services;
  final DateTime dayStart;
  final DateTime dayEnd;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final dayHeight = 24 * 60 * _pxPerMinute;
    final isToday = _EpgScreenState._jstDateOf(DateTime.now()) ==
        _EpgScreenState._jstDateOf(dayStart);
    final nowOffset = isToday
        ? DateTime.now().difference(dayStart).inMinutes * _pxPerMinute
        : null;
    return SingleChildScrollView(
      controller: controller,
      child: SizedBox(
        height: dayHeight,
        child: Stack(
          children: [
            // Hour gridlines.
            for (var hour = 0; hour <= 24; hour++)
              Positioned(
                top: hour * 60 * _pxPerMinute,
                left: 0,
                right: 0,
                child: const Divider(height: 1),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < services.length; i++)
                  SizedBox(
                    width: _channelWidth,
                    height: dayHeight,
                    child: Stack(
                      children: [
                        for (final event in services[i]
                            .events
                            .where((e) =>
                                e.end.isAfter(dayStart) &&
                                e.start.isBefore(dayEnd)))
                          _EventTile(
                            key: ValueKey(
                                '${services[i].channel.serviceId}-${event.eventId}-${event.start}'),
                            event: event,
                            channelName: services[i].channel.serviceName,
                            dayStart: dayStart,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            if (nowOffset != null && nowOffset >= 0 && nowOffset <= dayHeight)
              Positioned(
                top: nowOffset,
                left: 0,
                right: 0,
                child: Container(height: 2, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    super.key,
    required this.event,
    required this.channelName,
    required this.dayStart,
  });

  final EpgEvent event;
  final String channelName;
  final DateTime dayStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startMin = math.max(
        0, event.start.difference(dayStart).inMinutes);
    final endMin = math.min(
        24 * 60, event.end.difference(dayStart).inMinutes);
    final top = startMin * _pxPerMinute;
    final height = math.max(10, (endMin - startMin) * _pxPerMinute - 1);
    final title = event.title;
    final timeText = formatTimeJst(event.start);
    final timeStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
    );
    // Title lines that fit under the time line: the time line is
    // about 16px at the labelSmall size and a title line about
    // 17px, with 2px of vertical padding at each edge.
    final maxTitleLines = ((height - 4 - 16) / 17).floor();
    return Positioned(
      top: top,
      left: 1,
      right: 1,
      height: height.toDouble(),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
        // Tiles too short for their text must not paint outside
        // their box: spilled glyphs used to bleed into the tile
        // below and get half-covered there (plan 22).
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) =>
                _EventDetailDialog(event: event, channelName: channelName),
          ),
          child: maxTitleLines >= 1
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(timeText, style: timeStyle),
                      if (title != null)
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: maxTitleLines.clamp(1, 4),
                          ),
                        ),
                    ],
                  ),
                )
              : Padding(
                  // Compact form for tiles too short for two lines:
                  // time and title share one small line.
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        timeText,
                        style: timeStyle?.copyWith(fontSize: 10, height: 1.1),
                      ),
                      if (title != null) ...[
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 10, height: 1.1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _EventDetailDialog extends StatelessWidget {
  const _EventDetailDialog({required this.event, required this.channelName});

  final EpgEvent event;
  final String channelName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(event.title ?? '番組情報なし'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(channelName, style: theme.textTheme.bodySmall),
            Text(
              '${formatDateTimeWithWeekdayJst(event.start)} 〜 '
              '${formatTimeJst(event.end)}'
              '（${event.duration.inMinutes}分）',
              style: theme.textTheme.bodyMedium,
            ),
            if (event.shortText != null && event.shortText!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(event.shortText!),
            ],
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('番組内容', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(event.description!),
            ],
            if (event.cast != null && event.cast!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('出演者', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(event.cast!),
            ],
            for (final item in event.extendedItems) ...[
              const SizedBox(height: 12),
              Text(item.label, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(item.value),
            ],
            if (event.extendedText != null && event.extendedText!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(event.extendedText!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
