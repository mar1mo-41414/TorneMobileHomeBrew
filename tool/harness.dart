/// CLI harness for the tmhb core (plan 6 phase 1 completion criteria:
/// "discovery -> registration -> status -> schedules -> titles"
/// reproducible against the real device without the UI).
///
/// Usage:
///   dart run tool/harness.dart discover
///   dart run tool/harness.dart info   <host>
///   dart run tool/harness.dart live   <host>
///   dart run tool/harness.dart eitpf  <host>
///   dart run tool/harness.dart schedule-list   <host>
///   dart run tool/harness.dart schedule-cycle  <host>   (create->list->conflict->update->delete, test slot)
///   dart run tool/harness.dart titles <host>
///
/// Sensitive values (MAC address beyond the vendor prefix, HDD
/// serial, B-CAS card id, PIN, tokens) are never printed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:tmhb/core/core.dart';
import 'package:tmhb/core/services/device_info.dart';
import 'package:tmhb/core/services/discovery.dart';
import 'package:tmhb/core/services/metadata.dart';
import 'package:tmhb/core/services/registration.dart';
import 'package:tmhb/core/services/schedule_service.dart';
import 'package:tmhb/core/services/settings.dart';
import 'package:tmhb/core/services/title_catalog.dart';
import 'package:tmhb/core/transport/soap_transport.dart';
import 'package:tmhb/core/transport/webapi_transport.dart';

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
      priorityFlag: 1,
    ));
    final afterUpdate = await schedules.listSchedules();
    final updated = afterUpdate.firstWhere((s) => s.id == createdId);
    print('after update: priorityFlag=${updated.priorityFlag}');
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

Future<void> cmdTitles(String host) async {
  final (:reg, :device) = await registerHost(host);
  final xsrs = device.controlUrl(SoapServices.scheduledRecording.serviceType)!;
  final cds = device.controlUrl(SoapServices.contentDirectory.serviceType)!;
  final catalog = SoapTitleCatalogService(
    soap: SoapTransport(),
    xsrsControlUrl: xsrs,
    webApi: WebApiTransport(host),
    metadata: DlnaMetadataService(soap: SoapTransport(), controlUrl: cds),
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
