/// Subnet-scan discovery (plan 16.3): a unicast alternative to SSDP
/// for environments where multicast is unavailable — on iOS the
/// multicast entitlement cannot be obtained for sideloaded apps, and
/// SSDP discovery was measured not to work there (plan 16.2).
///
/// The scan derives the /24 subnets of this device's own private
/// IPv4 addresses, probes every host with a short-timeout WebAPI
/// request (the measured `status/boxNameGet` shape is the filter),
/// and identifies candidates by their device description — the same
/// identification rule as SSDP discovery (description content, plan
/// 5.2). When the description cannot be fetched, the measured
/// fallback control URLs are used, mirroring manual registration.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../endpoints.dart';
import '../models/device.dart';
import 'discovery.dart';
import 'interfaces.dart';

/// Supplies the subnet base prefixes to scan, each of the form
/// `192.168.11` (the /24 is implied). Injectable for tests.
typedef SubnetBaseProvider = Future<List<String>> Function();

bool _isPrivateIpv4(InternetAddress address) {
  final parts = address.address.split('.');
  if (parts.length != 4) return false;
  final a = int.tryParse(parts[0]) ?? -1;
  final b = int.tryParse(parts[1]) ?? -1;
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  return false;
}

/// Default [SubnetBaseProvider]: the /24 base of every private IPv4
/// address assigned to this device. dart:io exposes no netmask, so
/// /24 is assumed — the home-LAN norm (plan 16.3).
Future<List<String>> localSubnetBases() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  final bases = <String>{};
  for (final iface in interfaces) {
    for (final address in iface.addresses) {
      if (!_isPrivateIpv4(address)) continue;
      final parts = address.address.split('.');
      bases.add('${parts[0]}.${parts[1]}.${parts[2]}');
    }
  }
  return bases.toList()..sort();
}

/// Discovery by unicast subnet scan. See the library comment.
class SubnetScanDiscoveryService implements DiscoveryService {
  SubnetScanDiscoveryService({
    http.Client? client,
    this.probeTimeout = const Duration(milliseconds: 800),
    this.concurrency = 64,
    SubnetBaseProvider? subnetBases,
    this._describer,
  }) : _client = client ?? http.Client(),
       _subnetBases = subnetBases ?? localSubnetBases;

  final http.Client _client;

  /// Per-host probe timeout. One /24 sweep costs at most
  /// ceil(254 / [concurrency]) × [probeTimeout] (~3.2 s at the
  /// defaults); hosts that refuse or answer return far sooner.
  final Duration probeTimeout;

  /// Number of hosts probed in parallel.
  final int concurrency;

  final SubnetBaseProvider _subnetBases;

  /// Used for the authoritative description-based identification;
  /// defaults to the SSDP service's `describe` (transport only).
  final DiscoveryService? _describer;

  DiscoveryService get _describeService =>
      _describer ?? SsdpDiscoveryService(client: _client);

  @override
  Future<List<NasneDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    // [timeout] is the SSDP search window in the sibling
    // implementation; the scan is bounded by probeTimeout × batches
    // instead and ignores it.
    //
    // Subnets are scanned one at a time and the scan stops at the
    // first subnet that yields a device: a phone normally has a
    // single subnet anyway, and on multi-interface machines this
    // keeps dead virtual subnets (docker bridges, VPNs) from adding
    // their sweep time after the nasne has already been found.
    final bases = await _subnetBases();
    for (final base in bases) {
      final devices = await _scanSubnet(base);
      if (devices.isNotEmpty) return devices;
    }
    return const [];
  }

  Future<List<NasneDevice>> _scanSubnet(String base) async {
    final hosts = [for (var i = 1; i <= 254; i++) '$base.$i'];
    final candidates = <String>[];
    for (var start = 0; start < hosts.length; start += concurrency) {
      final batch = hosts.skip(start).take(concurrency);
      final results = await Future.wait([
        for (final host in batch) _probe(host).then((ok) => (host, ok)),
      ]);
      for (final (host, ok) in results) {
        if (ok) candidates.add(host);
      }
    }
    final devices = <NasneDevice>[];
    for (final host in candidates) {
      final device = await _identify(host);
      if (device != null) devices.add(device);
    }
    return devices;
  }

  /// Cheap filter: the nasne WebAPI answers `status/boxNameGet` with
  /// a JSON object carrying `errorcode: 0` and a `name`.
  Future<bool> _probe(String host) async {
    try {
      final resp = await _client
          .get(
            Uri(
              scheme: 'http',
              host: host,
              port: 64210,
              path: WebApiEndpoints.boxNameGet.path,
            ),
          )
          .timeout(probeTimeout);
      if (resp.statusCode != 200) return false;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      return decoded is Map &&
          decoded['errorcode'] == 0 &&
          decoded.containsKey('name');
    } catch (_) {
      return false;
    }
  }

  /// Authoritative identification by device description (plan 5.2),
  /// falling back to the measured direct control URLs when the
  /// description cannot be fetched — the manual-registration rule.
  Future<NasneDevice?> _identify(String host) async {
    try {
      final device = await _describeService.describe(
        Uri(scheme: 'http', host: host, port: 58888, path: '/'),
      );
      return device.isNasne ? device : null;
    } catch (_) {
      return NasneDevice.direct(host);
    }
  }

  @override
  Future<NasneDevice> describe(Uri location) =>
      _describeService.describe(location);
}

/// Runs every discovery implementation in order and merges
/// their results, deduplicated by host (plan 16.3, revised
/// after the 2026-11-23 Buffalo measurement below).
///
/// The original composition returned the first non-empty
/// result, with the subnet scan as a fallback for
/// multicast-restricted environments. Measured on a real
/// two-nasne home (Sony nasne + Buffalo NS-N100, 2026-11-23):
/// the Buffalo answers the WebAPI — registration, status,
/// titles, EPG, live and recorded playback all work once it
/// is registered — but it does not answer the SSDP search,
/// so SSDP found the Sony alone and the scan never ran.
/// First-non-empty therefore structurally misses a
/// SSDP-silent device whenever any other device answers.
/// Merging costs one scan sweep (bounded by probeTimeout ×
/// batches, ~3.2 s per subnet at the defaults) on every
/// search; the settings screen shows its searching state
/// meanwhile.
class CompositeDiscoveryService implements DiscoveryService {
  const CompositeDiscoveryService(this._chain);

  final List<DiscoveryService> _chain;

  @override
  Future<List<NasneDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final byHost = <String, NasneDevice>{};
    for (final service in _chain) {
      final found = await service.discover(timeout: timeout);
      for (final device in found) {
        byHost.putIfAbsent(device.host, () => device);
      }
    }
    return byHost.values.toList();
  }

  @override
  Future<NasneDevice> describe(Uri location) => _chain.first.describe(location);
}
