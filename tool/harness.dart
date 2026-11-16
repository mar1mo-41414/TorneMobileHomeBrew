/// CLI harness for the tmhb core (plan 6 phase 1 completion criteria:
/// "discovery -> registration -> status -> schedules -> titles"
/// reproducible against the real device without the UI).
///
/// Usage:
///   dart run tool/harness.dart discover
///   dart run tool/harness.dart info   `<host>`
///   dart run tool/harness.dart live   `<host>`
///   dart run tool/harness.dart eitpf  `<host>`
///   dart run tool/harness.dart schedule-list   `<host>`
///   dart run tool/harness.dart schedule-cycle  `<host>`   (create->list->conflict->update->delete, test slot)
///   dart run tool/harness.dart titles `<host>`
///
/// Sensitive values (MAC address beyond the vendor prefix, HDD
/// serial, B-CAS card id, PIN, tokens) are never printed.
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:tmhb/core/core.dart';

String maskMac(String mac) {
  final parts = mac.split(':');
  if (parts.length != 6) return '**:**:**:**:**:**';
  return '${parts[0]}:${parts[1]}:${parts[2]}:**:**:**';
}

String maskTail(String? value, [int keep = 0]) {
  if (value == null || value.isEmpty) return '(none)';
  if (keep <= 0) return '***';
  return '***${value.substring(value.length - keep)}';
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: harness <discover|info|live|eitpf|'
        'schedule-list|schedule-cycle|titles> [host]');
    exitCode = 64;
    return;
  }
  final command = args[0];
  try {
    switch (command) {
      case 'discover':
        await cmdDiscover();
      case 'info':
        await cmdInfo(args[1]);
      case 'live':
        await cmdLive(args[1]);
      case 'eitpf':
        await cmdEitpf(args[1]);
      case 'schedule-list':
        await cmdScheduleList(args[1]);
      case 'schedule-cycle':
        await cmdScheduleCycle(args[1]);
      case 'conflict-probe':
        await cmdConflictProbe(args[1]);
      case 'conflict-matrix':
        await cmdConflictMatrix(args[1]);
      case 'create-probe':
        await cmdCreateProbe(args[1]);
      case 'update-matrix':
        await cmdUpdateMatrix(args[1]);
      case 'titles':
        await cmdTitles(args[1]);
      default:
        stderr.writeln('unknown command: $command');
        exitCode = 64;
    }
  } on NasneError catch (e) {
    stderr.writeln('NasneError: $e');
    exitCode = 1;
  }
}

Future<void> cmdDiscover() async {
  final discovery = SsdpDiscoveryService();
  final devices = await discovery.discover();
  print('found ${devices.length} nasne device(s)');
  for (final d in devices) {
    print('- host=${d.host} name=${d.friendlyName} model=${d.modelName} '
        'udn=${d.udn} services=${d.services.length}');
    for (final s in d.services.values) {
      print('    ${s.serviceType} -> ${s.controlUrl}');
    }
  }
}

/// Registers (PINVerify) and returns the building blocks for [host].
Future<({RegisteredNasne reg, NasneDevice device})> registerHost(
    String host) async {
  final device = NasneDevice.direct(host);
  final registration = WebApiRegistrationService();
  final reg = await registration.register(device);
  // Prefer the described device (real control URLs) when reachable.
  NasneDevice described = device;
  try {
    described = await SsdpDiscoveryService()
        .describe(Uri.parse('http://$host:58888/'));
  } on NasneError {
    // fall back to the direct (fallback-URL) device
  }
  return (reg: reg, device: described);
}

WebApiDeviceInfoService infoService(String host) =>
    WebApiDeviceInfoService(WebApiTransport(host));

Future<void> cmdInfo(String host) async {
  final (:reg, device: _) = await registerHost(host);
  print('PINVerify: OK (host=${reg.host}, mac=${maskMac(reg.macAddr)}, '
      'udn=${reg.udn})');

  final info = infoService(host);
  final deviceInfo = await info.getDeviceInfo();
  print('name=${deviceInfo.name} version=${deviceInfo.softwareVersion} '
      'currDate=${deviceInfo.currDate} area=${deviceInfo.areaIdentifierCode} '
      'finishSetup=${deviceInfo.finishSetup} update=${deviceInfo.updateExists}');

  final hdds = await info.listHdds();
  for (final entry in hdds) {
    final detail = await info.getHddInfo(entry.id);
    print('hdd id=${detail.id} internal=${detail.internal} '
        'format=${detail.format} name=${detail.name} '
        'serial=${maskTail(detail.serialNumber)} '
        'total=${detail.totalBytes} free=${detail.freeBytes}');
  }

  final network = await info.getNetworkInfo();
  print('network ip=${network.ipv4Addr} mac=${maskMac(network.macAddr)} '
      'dhcp=${network.dhcpEnabled}');

  final bcas = await info.getBcasInfo();
  print('bcas cardId=${maskTail(bcas.cardId)} status=${bcas.status}');

  final channels = await info.listChannels(BroadcastingTypes.terrestrial);
  print('channels(terrestrial)=${channels.length}');
  for (final ch in channels.take(3)) {
    print('  ch=${ch.channelNumber} ${ch.serviceName} '
        'serviceId=${ch.serviceId} (${ch.serviceIdHex})');
  }

  final recNg = await info.listRecNg();
  print('recNg=${recNg.length}');
  final client = await info.getClientInfo();
  print('clientInfo registered=${client.registered} name=${client.name}');
}

Future<void> cmdLive(String host) async {
  final info = infoService(host);
  final live = await info.getLiveStatus();
  final gens = live.sections.entries
      .map((e) => '${e.key}=g${e.value.generation}')
      .join(' ');
  print('live sections: $gens');
  final eit = live.eitPf;
  print('EIT_PF generation=${eit.generation} populated=${eit.populated}');
  if (eit.present != null) {
    print('  present: ${eit.present!.title} @ ${eit.present!.startTime}');
  }
  if (eit.following != null) {
    print('  following: ${eit.following!.title} @ ${eit.following!.startTime}');
  }
  print('caMessages=${live.caMessages.length} '
      'emmMessages=${live.emmMessages.length} '
      'recNgInAggregate=${live.recNgItems.length}');
}

Future<void> cmdEitpf(String host) async {
  final transport = WebApiTransport(host);
  final json = await transport.getJson(WebApiEndpoints.liveStreamStatusListGet);
  const encoder = JsonEncoder.withIndent('  ');
  print(encoder.convert(json['EIT_PF']));
}

ScheduleService scheduleService(NasneDevice device) {
  final control = device.controlUrl(SoapServices.scheduledRecording.serviceType);
  if (control == null) {
    throw NasneError.validation('harness', 'no XSRS control URL');
  }
  return SoapScheduleService(
    soap: SoapTransport(),
    controlUrl: control,
  );
}

Future<void> cmdScheduleList(String host) async {
  final (:reg, :device) = await registerHost(host);
  final schedules = scheduleService(device);
  final list = await schedules.listSchedules();
  print('schedules=${list.length}');
  for (final s in list) {
    print('- id=${s.id} start=${s.start} dur=${s.durationSeconds}s '
        'ch=${s.channel.serviceIdHex} q=${s.desiredQualityMode} '
        'title=${s.title}');
  }
}

Future<void> cmdScheduleCycle(String host) async {
  final (:reg, :device) = await registerHost(host);
  final info = infoService(host);
  final channels = await info.listChannels(BroadcastingTypes.terrestrial);
  final channel = channels.first;
  final schedules = scheduleService(device);

  // Test slot: two days ahead, 04:00 local, 300 seconds (plan 7).
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day + 2, 4, 0, 0);
  final candidate = NewRecordSchedule(
    start: start,
    durationSeconds: 300,
    channel: ScheduleChannel(
      broadcastingType: BroadcastingTypes.terrestrial,
      channelType: 2,
      serviceId: channel.serviceId,
    ),
    networkId: channel.networkId,
  );

  final before = await schedules.listSchedules();
  print('before: ${before.length} schedule(s)');

  String? createdId;
  try {
    createdId = await schedules.createSchedule(candidate);
    print('created: normalised id=$createdId');

    final after = await schedules.listSchedules();
    final mine = after.where((s) => s.id == createdId).toList();
    print('after create: ${after.length} schedule(s), '
        'mine found=${mine.isNotEmpty}');
    if (mine.isEmpty) {
      throw StateError('created schedule not found in list');
    }

    final conflicts = await schedules.checkConflicts(candidate);
    print('conflicts for candidate: ${conflicts.length}');

    await schedules.updateSchedule(ScheduleUpdate(
      id: createdId,
      conditionId: mine.single.conditionId,
      priorityFlag: 1,
    ));
    final afterUpdate = await schedules.listSchedules();
    final updated = afterUpdate.firstWhere((s) => s.id == createdId);
    // The device accepts the update shape but does not necessarily
    // reflect the values (phase 1 matrix); print the re-read truth.
    print('after update: priorityFlag=${updated.priorityFlag} '
        'quality=${updated.desiredQualityMode} '
        'condition=${updated.conditionId}');
  } finally {
    if (createdId != null) {
      await schedules.deleteSchedule(createdId);
      final afterDelete = await schedules.listSchedules();
      final gone = afterDelete.every((s) => s.id != createdId);
      print('after delete: ${afterDelete.length} schedule(s), '
          'mine gone=$gone');
    }
  }
}

/// Raw observation of X_GetConflictList behaviour: calls the action
/// directly and then through the service, so the Fault shape (if
/// any) and the parsed result are both visible.
Future<void> cmdConflictProbe(String host) async {
  final (:reg, :device) = await registerHost(host);
  final info = infoService(host);
  final channels = await info.listChannels(BroadcastingTypes.terrestrial);
  final channel = channels.first;
  final schedules = scheduleService(device);
  final list = await schedules.listSchedules();

  final now = DateTime.now();
  final candidate = NewRecordSchedule(
    start: DateTime(now.year, now.month, now.day + 2, 4, 0, 0),
    durationSeconds: 300,
    channel: ScheduleChannel(
      broadcastingType: BroadcastingTypes.terrestrial,
      channelType: 2,
      serviceId: channel.serviceId,
    ),
    networkId: channel.networkId,
  );

  print('schedules on device: ${list.length}');
  final control =
      device.controlUrl(SoapServices.scheduledRecording.serviceType)!;
  final elements = buildXsrsDocument(buildCreateItemXml(candidate));
  try {
    final resp = await SoapTransport().call(
      controlUrl: control,
      serviceType: SoapServices.scheduledRecording.serviceType,
      action: 'X_GetConflictList',
      args: {'Elements': elements},
    );
    print('raw X_GetConflictList (full template): OK, Result length='
        '${resp.result?.length ?? -1}');
  } on NasneError catch (e) {
    print('raw X_GetConflictList (full template): NasneError '
        'category=${e.category.name} code=${e.code} retryable=${e.retryable}');
  }

  // Shape control: the phase 0 minimal candidate (no
  // desiredMatchingID) faulted with 402. Reproduce that shape here to
  // decide whether the Fault tracks the candidate shape rather than
  // the reservation count.
  final startText = formatNasneDateTime(candidate.start);
  final minimal = buildXsrsDocument(
      '<item id=""><scheduledStartDateTime>$startText</scheduledStartDateTime>'
      '<scheduledDuration>300</scheduledDuration>'
      '<scheduledConditionID></scheduledConditionID>'
      '<scheduledChannelID broadcastingType="2" channelType="2">'
      '${candidate.channel.serviceIdHex}</scheduledChannelID>'
      '<desiredQualityMode>100</desiredQualityMode>'
      '<reservationCreatorID>2000</reservationCreatorID>'
      '<priorityFlag>0</priorityFlag>'
      '<recordDestinationID>HDD</recordDestinationID></item>');
  try {
    final resp = await SoapTransport().call(
      controlUrl: control,
      serviceType: SoapServices.scheduledRecording.serviceType,
      action: 'X_GetConflictList',
      args: {'Elements': minimal},
    );
    print('raw X_GetConflictList (minimal, no desiredMatchingID): OK, '
        'Result length=${resp.result?.length ?? -1}');
  } on NasneError catch (e) {
    print('raw X_GetConflictList (minimal, no desiredMatchingID): '
        'NasneError category=${e.category.name} code=${e.code}');
  }
  final viaService = await schedules.checkConflicts(candidate);
  print('service checkConflicts: ${viaService.length} conflict(s)');
}

/// Variant matrix for the X_GetConflictList 402 Fault: replays the
/// exact phase 0 write_probe2 candidate shape and single-change
/// variants, to isolate which property the device rejects.
Future<void> cmdConflictMatrix(String host) async {
  final (:reg, :device) = await registerHost(host);
  final control =
      device.controlUrl(SoapServices.scheduledRecording.serviceType)!;
  final soap = SoapTransport();

  String item({
    required String start,
    bool title = false,
    bool condition = true,
    bool matching = true,
  }) {
    final b = StringBuffer('<item id="">');
    if (title) b.write('<title>tmhb phase0 test</title>');
    b.write('<scheduledStartDateTime>$start</scheduledStartDateTime>');
    b.write('<scheduledDuration>300</scheduledDuration>');
    if (condition) b.write('<scheduledConditionID></scheduledConditionID>');
    b.write('<scheduledChannelID broadcastingType="2" channelType="2">'
        '0xde00</scheduledChannelID>');
    if (matching) {
      b.write('<desiredMatchingID type="SI_PROGRAMID">,,0x7880,0x0000'
          '</desiredMatchingID>');
    }
    b.write('<desiredQualityMode>100</desiredQualityMode>');
    b.write('<reservationCreatorID>2000</reservationCreatorID>');
    b.write('<priorityFlag>0</priorityFlag>');
    b.write('<recordDestinationID>HDD</recordDestinationID>');
    b.write('</item>');
    return b.toString();
  }

  final variants = <String, String>{
    // The exact write_probe2 candidate (faulted in phase 0).
    'phase0-exact (title, +0900, no condition, no matching)': item(
        start: '2026-11-18T04:00:00+0900',
        title: true,
        condition: false,
        matching: false),
    // Single change: colon-form datetime.
    'phase0 + colon datetime': item(
        start: '2026-11-18T04:00:00+09:00',
        title: true,
        condition: false,
        matching: false),
    // Single change: no title element.
    'phase0 - title': item(
        start: '2026-11-18T04:00:00+0900',
        condition: false,
        matching: false),
    // Single change: scheduledConditionID present.
    'phase0 + condition': item(
        start: '2026-11-18T04:00:00+0900',
        title: true,
        matching: false),
    // Single change: desiredMatchingID present.
    'phase0 + matching': item(
        start: '2026-11-18T04:00:00+0900', title: true, condition: false),
  };

  for (final entry in variants.entries) {
    try {
      final resp = await soap.call(
        controlUrl: control,
        serviceType: SoapServices.scheduledRecording.serviceType,
        action: 'X_GetConflictList',
        args: {'Elements': buildXsrsDocument(entry.value)},
      );
      print('${entry.key}: OK (Result ${resp.result?.length ?? -1} chars)');
    } on NasneError catch (e) {
      print('${entry.key}: Fault category=${e.category.name} code=${e.code}');
    }
  }
}

/// Create-side shape probe: tries a create WITHOUT desiredMatchingID
/// (colon datetime, otherwise the full template). Phase 0 attributed
/// the minimal form's 402 to the missing matching id, but that
/// candidate also used the compact +0900 datetime, which the conflict
/// matrix proved is itself rejected. Whatever is created here is
/// deleted again before returning.
Future<void> cmdCreateProbe(String host) async {
  final (:reg, :device) = await registerHost(host);
  final control =
      device.controlUrl(SoapServices.scheduledRecording.serviceType)!;
  final soap = SoapTransport();
  final schedules = scheduleService(device);

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day + 2, 4, 0, 0);
  final item = '<item id="">'
      '<scheduledStartDateTime>${formatNasneDateTime(start)}</scheduledStartDateTime>'
      '<scheduledDuration>300</scheduledDuration>'
      '<scheduledConditionID></scheduledConditionID>'
      '<scheduledChannelID broadcastingType="2" channelType="2">0xde00</scheduledChannelID>'
      '<desiredQualityMode>100</desiredQualityMode>'
      '<reservationCreatorID>2000</reservationCreatorID>'
      '<priorityFlag>0</priorityFlag>'
      '<recordDestinationID>HDD</recordDestinationID></item>';
  String? createdId;
  try {
    final resp = await soap.call(
      controlUrl: control,
      serviceType: SoapServices.scheduledRecording.serviceType,
      action: 'X_CreateRecordSchedule',
      args: {'Elements': buildXsrsDocument(item)},
    );
    createdId = resp.values['RecordScheduleID'];
    print('create without desiredMatchingID: OK, '
        'RecordScheduleID=$createdId');
  } on NasneError catch (e) {
    print('create without desiredMatchingID: Fault '
        'category=${e.category.name} code=${e.code}');
  } finally {
    if (createdId != null) {
      final id = normalizeScheduleId(createdId);
      final list = await schedules.listSchedules();
      print('list contains it: ${list.any((s) => s.id == id)}');
      await schedules.deleteSchedule(id);
      final after = await schedules.listSchedules();
      print('after delete: ${after.length} schedule(s)');
    }
  }
}

/// Update-shape matrix: phase 0's successful sparse update carried
/// condition+quality+priority together; a priority-only update was
/// rejected with 853 in the phase 1 cycle. Each variant runs its own
/// create -> update -> delete round-trip.
Future<void> cmdUpdateMatrix(String host) async {
  final (:reg, :device) = await registerHost(host);
  final control =
      device.controlUrl(SoapServices.scheduledRecording.serviceType)!;
  final soap = SoapTransport();
  final schedules = scheduleService(device);
  final info = infoService(host);
  final channels = await info.listChannels(BroadcastingTypes.terrestrial);
  final channel = channels.first;

  final now = DateTime.now();
  final candidate = NewRecordSchedule(
    start: DateTime(now.year, now.month, now.day + 2, 4, 0, 0),
    durationSeconds: 300,
    channel: ScheduleChannel(
      broadcastingType: BroadcastingTypes.terrestrial,
      channelType: 2,
      serviceId: channel.serviceId,
    ),
    networkId: channel.networkId,
  );

  Future<void> variant(String name, Map<String, String> fields) async {
    final id = await schedules.createSchedule(candidate);
    try {
      final item = StringBuffer('<item id="$id">');
      for (final e in fields.entries) {
        item.write('<${e.key}>${e.value}</${e.key}>');
      }
      item.write('</item>');
      try {
        await soap.call(
          controlUrl: control,
          serviceType: SoapServices.scheduledRecording.serviceType,
          action: 'X_UpdateRecordSchedule',
          args: {'Elements': buildXsrsDocument(item.toString())},
        );
        final after = await schedules.listSchedules();
        final mine = after.firstWhere((s) => s.id == id);
        print('$name: OK -> priority=${mine.priorityFlag} '
            'quality=${mine.desiredQualityMode} '
            'condition=${mine.conditionId}');
      } on NasneError catch (e) {
        print('$name: Fault code=${e.code}');
      }
    } finally {
      await schedules.deleteSchedule(id);
    }
  }

  await variant('priority only', {'priorityFlag': '1'});
  await variant('condition+priority',
      {'scheduledConditionID': '1', 'priorityFlag': '1'});
  await variant('condition only', {'scheduledConditionID': '1'});
  await variant('quality+priority',
      {'desiredQualityMode': '100', 'priorityFlag': '1'});
  await variant('condition+quality+priority', {
    'scheduledConditionID': '1',
    'desiredQualityMode': '100',
    'priorityFlag': '1',
  });
  await variant('condition+quality',
      {'scheduledConditionID': '1', 'desiredQualityMode': '100'});
  await variant('quality+destination',
      {'desiredQualityMode': '100', 'recordDestinationID': 'HDD'});
  await variant('destination only', {'recordDestinationID': 'HDD'});
  final end = await schedules.listSchedules();
  print('final schedules: ${end.length}');
}

Future<void> cmdTitles(String host) async {
  final (:reg, :device) = await registerHost(host);
  final xsrs = device.controlUrl(SoapServices.scheduledRecording.serviceType)!;
  final cds = device.controlUrl(SoapServices.contentDirectory.serviceType)!;
  final catalog = SoapTitleCatalogService(
    soap: SoapTransport(),
    xsrsControlUrl: xsrs,
    webApi: WebApiTransport(host),
    metadata: CompositeMetadataService(
      dlna: DlnaMetadataService(soap: SoapTransport(), controlUrl: cds),
      epg: WebApiEpgService(
        plain: WebApiTransport(host),
        authed: WebApiTransport(host, tokenProvider: reg.tokenProvider),
      ),
    ),
  );
  final count = await catalog.countTitles();
  final titles = await catalog.listTitles();
  print('count=$count titles=${titles.length}');
  for (final t in titles) {
    print('- id=${t.id} title=${t.title} start=${t.scheduledStart} '
        'dur=${t.scheduledDurationSeconds}s cog=${t.copyCountRemaining} '
        'res=${t.res.length} chName=${t.channelName}');
    for (final r in t.res) {
      print('    res quality=${r.quality} dtcp=${r.dtcpHost}:${r.dtcpPort} '
          'dur=${r.duration} cleartext=${r.cleartextSize}');
    }
  }
}
