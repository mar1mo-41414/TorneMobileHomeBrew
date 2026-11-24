/// Subnet-scan discovery + composite chain (plan 16.3), against a
/// MockClient. 192.0.2.0/24 is TEST-NET-1; .7 identifies by
/// description, .9 answers the WebAPI probe but its description is
/// unreachable (direct fallback), everything else is absent.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tmhb/core/core.dart';

class _FakeDescriber implements DiscoveryService {
  final List<String> describedHosts = [];

  @override
  Future<NasneDevice> describe(Uri location) async {
    describedHosts.add(location.host);
    if (location.host == '192.0.2.7') {
      return NasneDevice(
        host: location.host,
        descriptionUrl: location,
        friendlyName: 'nasne',
        modelName: 'nasne',
        manufacturer: 'Sony Computer Entertainment Inc.',
        udn: 'uuid:fake-1',
        services: const {},
      );
    }
    throw NasneError.unreachable('test:describe');
  }

  @override
  Future<List<NasneDevice>> discover({Duration timeout = Duration.zero}) =>
      throw UnimplementedError();
}

MockClient _scanClient() {
  return MockClient((request) async {
    final url = request.url;
    if (url.port == 64210 && url.path == '/status/boxNameGet') {
      if (url.host == '192.0.2.7' || url.host == '192.0.2.9') {
        return http.Response(
          jsonEncode({'errorcode': 0, 'name': 'nasne'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (url.host == '192.0.2.8') {
        // Something answers but is not a nasne WebAPI shape.
        return http.Response('{"errorcode": 3}', 200);
      }
      throw http.ClientException('no route to host', url);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  test('scan probes the subnet, identifies by description, falls back '
      'to direct when the description is unreachable', () async {
    final describer = _FakeDescriber();
    final service = SubnetScanDiscoveryService(
      client: _scanClient(),
      subnetBases: () async => ['192.0.2'],
      describer: describer,
      probeTimeout: const Duration(seconds: 1),
    );
    final found = await service.discover();
    expect(found.map((d) => d.host), ['192.0.2.7', '192.0.2.9']);
    // .7 came from the description; .9 fell back to the direct form.
    expect(found[0].udn, 'uuid:fake-1');
    expect(found[1].isNasne, isTrue);
    expect(
      found[1].controlUrl(
        'urn:schemas-xsrs-org:service:X_ScheduledRecording:2',
      ),
      Uri.parse('http://192.0.2.9:64230/XSRS'),
    );
    expect(describer.describedHosts, ['192.0.2.7', '192.0.2.9']);
  });

  test('scan stops at the first subnet that yields a device', () async {
    final probed = <String>{};
    final client = MockClient((request) async {
      probed.add(request.url.host);
      if (request.url.host == '192.0.2.7' &&
          request.url.path == '/status/boxNameGet') {
        return http.Response(
          jsonEncode({'errorcode': 0, 'name': 'nasne'}),
          200,
        );
      }
      throw http.ClientException('no route to host', request.url);
    });
    final service = SubnetScanDiscoveryService(
      client: client,
      subnetBases: () async => ['192.0.2', '198.51.100'],
      describer: _FakeDescriber(),
    );
    final found = await service.discover();
    expect(found.map((d) => d.host), ['192.0.2.7']);
    expect(probed.any((h) => h.startsWith('198.51.100.')), isFalse);
  });

  test('scan finds nothing on an empty subnet', () async {
    final service = SubnetScanDiscoveryService(
      client: _scanClient(),
      subnetBases: () async => ['198.51.100'],
      describer: _FakeDescriber(),
    );
    expect(await service.discover(), isEmpty);
  });

  group('CompositeDiscoveryService', () {
    NasneDevice device(String host) => NasneDevice.direct(host);

    test('falls through to the scan when SSDP finds nothing', () async {
      final order = <String>[];
      final composite = CompositeDiscoveryService([
        _StubDiscovery('ssdp', [], order),
        _StubDiscovery('scan', [device('192.0.2.7')], order),
      ]);
      final found = await composite.discover();
      expect(found.map((d) => d.host), ['192.0.2.7']);
      expect(order, ['ssdp', 'scan']);
    });

    test('merges the results of every implementation', () async {
      final order = <String>[];
      final composite = CompositeDiscoveryService([
        _StubDiscovery('ssdp', [device('192.0.2.7')], order),
        _StubDiscovery('scan', [device('192.0.2.9')], order),
      ]);
      final found = await composite.discover();
      expect(found.map((d) => d.host), ['192.0.2.7', '192.0.2.9']);
      expect(order, ['ssdp', 'scan']);
    });

    test('deduplicates a host reported by both', () async {
      final composite = CompositeDiscoveryService([
        _StubDiscovery('ssdp', [device('192.0.2.7')], []),
        _StubDiscovery('scan', [device('192.0.2.7')], []),
      ]);
      final found = await composite.discover();
      expect(found.map((d) => d.host), ['192.0.2.7']);
    });
  });
}

class _StubDiscovery implements DiscoveryService {
  _StubDiscovery(this.name, this.result, this.calls);

  final String name;
  final List<NasneDevice> result;
  final List<String> calls;

  @override
  Future<List<NasneDevice>> discover({Duration timeout = Duration.zero}) async {
    calls.add(name);
    return result;
  }

  @override
  Future<NasneDevice> describe(Uri location) => throw UnimplementedError();
}
