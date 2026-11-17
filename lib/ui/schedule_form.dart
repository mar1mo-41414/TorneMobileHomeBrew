/// Reservation create / edit forms (plan 5.6 item 2, 12.5, 12.7).
///
/// The forms encode the measured device contract (plan 11.7, 13.6,
/// 13.7):
///  * create sends the full torne template (built by the core from
///    [NewRecordSchedule]); before creating, the candidate is checked
///    with `X_GetConflictList` and conflicts are shown as a warning
///    the user can accept or cancel;
///  * edit is a sparse update: `priorityFlag` is always sent and at
///    least one change field is included (the three changeable fields
///    are always submitted with their control values);
///  * start time and duration cannot be updated, so a time change is
///    modelled as create-then-delete of the original reservation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'error_messages.dart';
import 'format.dart';
import 'widgets.dart';

enum ScheduleFormMode { create, edit, timeChange }

/// Programme data prefilled into the create form from the EPG
/// (plan 28): the event's service, start, duration and texts. The
/// create itself goes through the same XSRS path as a manual
/// reservation; the event id is carried into the candidate's
/// desiredMatchingID, like torne's own EPG reservations.
class SchedulePrefill {
  const SchedulePrefill({
    required this.channel,
    required this.start,
    required this.durationSeconds,
    required this.eventId,
    this.title,
    this.description,
  });

  final Channel channel;
  final DateTime start;
  final int durationSeconds;
  final int eventId;
  final String? title;
  final String? description;
}

class ScheduleFormPage extends ConsumerStatefulWidget {
  const ScheduleFormPage({
    super.key,
    required this.reg,
    required this.mode,
    this.original,
    this.prefill,
  });

  factory ScheduleFormPage.create(RegisteredNasne reg) =>
      ScheduleFormPage(reg: reg, mode: ScheduleFormMode.create);

  /// Create form prefilled from a programme-guide event (plan 28).
  factory ScheduleFormPage.fromEpg(
    RegisteredNasne reg, {
    required Channel channel,
    required EpgEvent event,
  }) => ScheduleFormPage(
    reg: reg,
    mode: ScheduleFormMode.create,
    prefill: SchedulePrefill(
      channel: channel,
      start: event.start,
      durationSeconds: event.duration.inSeconds,
      eventId: event.eventId,
      title: event.title,
      description: event.description ?? event.shortText,
    ),
  );

  factory ScheduleFormPage.edit(RegisteredNasne reg, RecordSchedule original) =>
      ScheduleFormPage(
        reg: reg,
        mode: ScheduleFormMode.edit,
        original: original,
      );

  factory ScheduleFormPage.timeChange(
    RegisteredNasne reg,
    RecordSchedule original,
  ) => ScheduleFormPage(
    reg: reg,
    mode: ScheduleFormMode.timeChange,
    original: original,
  );

  final RegisteredNasne reg;
  final ScheduleFormMode mode;
  final RecordSchedule? original;

  /// EPG prefill for the create form (plan 28); null for the
  /// manual create / edit / time-change forms.
  final SchedulePrefill? prefill;

  @override
  ConsumerState<ScheduleFormPage> createState() => _ScheduleFormPageState();
}

class _ScheduleFormPageState extends ConsumerState<ScheduleFormPage> {
  // create / timeChange fields
  int? _serviceId;
  late DateTime _date; // JST wall date (fields only)
  late TimeOfDay _time;
  final _durationMinutes = TextEditingController(text: '60');
  // shared fields
  late int _quality;
  late bool _priority;
  // edit fields
  final _condition = TextEditingController();
  final _destination = TextEditingController();

  bool _saving = false;

  bool get _isEdit => widget.mode == ScheduleFormMode.edit;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    if (original != null) {
      _quality = original.desiredQualityMode;
      _priority = original.priorityFlag != 0;
      _condition.text = original.conditionId;
      _destination.text = original.recordDestinationId;
      final wall = jstWallClock(original.start);
      _date = DateTime(wall.year, wall.month, wall.day);
      _time = TimeOfDay(hour: wall.hour, minute: wall.minute);
      _durationMinutes.text = '${original.durationSeconds ~/ 60}';
      _serviceId = original.channel.serviceId;
    } else {
      _quality = 100;
      _priority = false;
      final prefill = widget.prefill;
      if (prefill != null) {
        // EPG prefill (plan 28): service, start and duration come
        // from the event; the quality stays the user's choice.
        _serviceId = prefill.channel.serviceId;
        final wall = jstWallClock(prefill.start);
        _date = DateTime(wall.year, wall.month, wall.day);
        _time = TimeOfDay(hour: wall.hour, minute: wall.minute);
        final minutes = (prefill.durationSeconds / 60).round();
        _durationMinutes.text = '${minutes < 1 ? 1 : minutes}';
      } else {
        final wall = jstWallClock(DateTime.now().add(const Duration(hours: 1)));
        _date = DateTime(wall.year, wall.month, wall.day);
        _time = TimeOfDay(hour: wall.hour, minute: 0);
      }
    }
  }

  @override
  void dispose() {
    _durationMinutes.dispose();
    _condition.dispose();
    _destination.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    ScheduleFormMode.create =>
      widget.prefill != null ? '番組を予約' : '新規予約',
    ScheduleFormMode.edit => '予約の編集',
    ScheduleFormMode.timeChange => '予約時刻の変更',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _isEdit ? _buildEditForm(context) : _buildCreateForm(context),
    );
  }

  // -------------------------------------------------------------------------
  // Create / time-change form
  // -------------------------------------------------------------------------

  Widget _buildCreateForm(BuildContext context) {
    final channels = ref.watch(channelsProvider(widget.reg));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.prefill != null) ...[
          // The programme being reserved (plan 28): shown for
          // confirmation; the fields below start from its values
          // and stay editable.
          Text(
            widget.prefill!.title ?? '番組情報なし',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.prefill!.channel.serviceName} / '
            '${formatDateTimeWithWeekdayJst(widget.prefill!.start)} 〜 '
            '${formatTimeJst(widget.prefill!.start.add(Duration(seconds: widget.prefill!.durationSeconds)))}',
          ),
          if (widget.prefill!.description != null &&
              widget.prefill!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(widget.prefill!.description!),
          ],
          const SizedBox(height: 16),
        ],
        if (widget.mode == ScheduleFormMode.timeChange)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('時刻の変更は、元の予約を削除して新しい予約を作成することで行います。'),
          ),
        asyncSection(channels, (list) {
          if (list.isEmpty) {
            return const Text('チャンネル一覧が空です');
          }
          final ids = {for (final c in list) c.serviceId};
          final value = ids.contains(_serviceId)
              ? _serviceId
              : list.first.serviceId;
          return DropdownButtonFormField<int>(
            initialValue: value,
            decoration: const InputDecoration(labelText: 'チャンネル'),
            items: [
              for (final c in list)
                DropdownMenuItem(
                  value: c.serviceId,
                  child: Text(c.serviceName),
                ),
            ],
            onChanged: (v) => setState(() => _serviceId = v),
          );
        }, onRetry: () => ref.invalidate(channelsProvider(widget.reg))),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                '日付: ${formatDateJst(instantFromJstWall(_date))} '
                '(${formatWeekdayJst(instantFromJstWall(_date))})',
              ),
            ),
            TextButton(onPressed: _pickDate, child: const Text('日付を選択')),
          ],
        ),
        Row(
          children: [
            Expanded(child: Text('開始時刻: ${_time.format(context)}')),
            TextButton(onPressed: _pickTime, child: const Text('時刻を選択')),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _durationMinutes,
          decoration: const InputDecoration(
            labelText: '長さ (分)',
            suffixText: '分',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        _qualityField(),
        SwitchListTile(
          title: const Text('優先フラグ'),
          value: _priority,
          onChanged: (v) => setState(() => _priority = v),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _saveCreate,
          child: Text(_saving ? '送信中…' : '予約を作成'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 2),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Widget _qualityField() {
    // The measured torne values in the XSRS space (plan 28):
    // 100 = DR, 230 = 3倍. An existing reservation's own value is
    // always offered as well, so editing never silently rewrites
    // an unlisted value.
    final options = <int>{
      100,
      230,
      if (widget.original != null) widget.original!.desiredQualityMode,
    }.toList()..sort();
    return DropdownButtonFormField<int>(
      initialValue: _quality,
      decoration: const InputDecoration(labelText: '画質モード'),
      items: [
        for (final q in options)
          DropdownMenuItem(value: q, child: Text(qualityModeLabel(q))),
      ],
      onChanged: (v) => setState(() => _quality = v ?? _quality),
    );
  }

  Future<void> _saveCreate() async {
    final channels = ref.read(channelsProvider(widget.reg)).value;
    Channel? channel;
    if (channels != null) {
      for (final c in channels) {
        if (c.serviceId == (_serviceId ?? channels.firstOrNull?.serviceId)) {
          channel = c;
          break;
        }
      }
    }
    if (channel == null) {
      showSnack(context, 'チャンネルを選択してください');
      return;
    }
    final minutes = int.tryParse(_durationMinutes.text.trim());
    if (minutes == null || minutes < 1 || minutes > 1440) {
      showSnack(context, '長さは 1〜1440 分で入力してください');
      return;
    }
    final start = instantFromJstWall(
      DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute),
    );
    final candidate = NewRecordSchedule(
      start: start,
      durationSeconds: minutes * 60,
      channel: ScheduleChannel(
        broadcastingType: channel.broadcastingType,
        channelType: channel.broadcastingType,
        serviceId: channel.serviceId,
      ),
      networkId: channel.networkId,
      eventId: widget.prefill?.eventId ?? 0,
      desiredQualityMode: _quality,
      priorityFlag: _priority ? 1 : 0,
      // torne's create template pairs the destination with the
      // quality profile (plan 28, torne-created samples): DR
      // carries 'HDD', 3倍 carries 'USBHDD'. The value is the
      // template's desired destination; the recording itself
      // lands on the internal HDD either way.
      recordDestinationId: _quality == 230 ? 'USBHDD' : 'HDD',
    );

    setState(() => _saving = true);
    final services = ref.read(deviceServicesProvider(widget.reg));
    try {
      var conflicts = await services.schedules.checkConflicts(candidate);
      final original = widget.original;
      if (widget.mode == ScheduleFormMode.timeChange && original != null) {
        // The reservation being replaced always overlaps itself; it is
        // not a conflict for this flow (plan 12.7 time-change model).
        conflicts = [
          for (final c in conflicts)
            if (c.id != original.id) c,
        ];
      }
      if (conflicts.isNotEmpty) {
        if (!mounted) return;
        final proceed = await _showConflictWarning(conflicts, channels);
        if (proceed != true) {
          setState(() => _saving = false);
          return;
        }
      }
      await services.schedules.createSchedule(candidate);
      if (widget.mode == ScheduleFormMode.timeChange && original != null) {
        await services.schedules.deleteSchedule(original.id);
      }
    } on NasneError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, userMessageForError(e));
      return;
    }
    ref.invalidate(schedulesProvider(widget.reg));
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(context, '予約を作成しました');
  }

  Future<bool?> _showConflictWarning(
    List<RecordSchedule> conflicts,
    List<Channel>? channels,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('競合する予約があります'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('次の既存予約と時間が重なります:'),
            const SizedBox(height: 8),
            for (final c in conflicts)
              Text(
                '・${formatDateTimeJst(c.start)} '
                '${channelDisplayName(channels, c.channel)} '
                '(${formatDurationSeconds(c.durationSeconds)})',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('このまま作成'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Edit (sparse update) form
  // -------------------------------------------------------------------------

  Widget _buildEditForm(BuildContext context) {
    final original = widget.original!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FieldRow(
          label: '開始',
          value: formatDateTimeWithWeekdayJst(original.start),
        ),
        FieldRow(
          label: '長さ',
          value: formatDurationSeconds(original.durationSeconds),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('開始時刻と長さは編集では変更できません。「時刻を変更」から行ってください。'),
        ),
        const SizedBox(height: 8),
        _qualityField(),
        SwitchListTile(
          title: const Text('優先フラグ'),
          value: _priority,
          onChanged: (v) => setState(() => _priority = v),
        ),
        TextField(
          controller: _condition,
          decoration: const InputDecoration(labelText: '条件 ID'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _destination,
          decoration: const InputDecoration(labelText: '録画先'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _saveEdit,
          child: Text(_saving ? '送信中…' : '更新する'),
        ),
      ],
    );
  }

  Future<void> _saveEdit() async {
    final original = widget.original!;
    final condition = _condition.text.trim();
    final destination = _destination.text.trim();
    final priority = _priority ? 1 : 0;
    final changed =
        _quality != original.desiredQualityMode ||
        priority != original.priorityFlag ||
        condition != original.conditionId ||
        destination != original.recordDestinationId;
    if (!changed) {
      showSnack(context, '変更がありません');
      return;
    }
    if (destination.isEmpty) {
      showSnack(context, '録画先を入力してください');
      return;
    }
    // Measured contract (plan 13.7): priorityFlag is mandatory and at
    // least one change field must accompany it. All three changeable
    // fields are always submitted, so the contract holds by shape.
    final update = ScheduleUpdate(
      id: original.id,
      priorityFlag: priority,
      conditionId: condition,
      desiredQualityMode: _quality,
      recordDestinationId: destination,
    );
    setState(() => _saving = true);
    try {
      await ref
          .read(deviceServicesProvider(widget.reg))
          .schedules
          .updateSchedule(update);
    } on NasneError catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, userMessageForError(e));
      return;
    }
    // After an update the re-read value is the truth (plan 12.5).
    ref.invalidate(schedulesProvider(widget.reg));
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(context, '更新しました');
  }
}
