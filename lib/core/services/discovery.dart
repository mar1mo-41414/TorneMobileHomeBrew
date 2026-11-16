/// DiscoveryService implementation: SSDP + device description
/// (plan 5.2 / 11.2 / 12.1).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../errors.dart';
import '../models/device.dart';
import '../transport/ssdp_transport.dart';
import '../transport/xml_util.dart';
import 'interfaces.dart';

class SsdpDiscoveryService implements DiscoveryService {
  SsdpDiscoveryService({
    SsdpTransport? ssdp,
    http.Client? client,
    this.httpTimeout = const Duration(seconds: 10),
  })  : _ssdp = ssdp ?? const SsdpTransport(),
        _client = client ?? http.Client();

  final SsdpTransport _ssdp;
  final http.Client _client;
  final Duration httpTimeout;

  static const String mediaServerSearchTarget =
      'urn:schemas-upnp-org:device:MediaServer:1';

  @override
  Future<List<NasneDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final responses = await _ssdp.search(mediaServerSearchTarget,
        timeout: timeout);
    final locations = <String>{};
    for (final r in responses) {
      final loc = r.location;
      if (loc != null && loc.isNotEmpty) locations.add(loc);
    }
    final devices = <NasneDevice>[];
    for (final loc in locations) {
      try {
        final device = await describe(Uri.parse(loc));
        if (device.isNasne) devices.add(device);
      } on NasneError {
        // Not a nasne (or gone): discovery skips it by design.
        continue;
      }
    }
    return devices;
  }

  @override
  Future<NasneDevice> describe(Uri location) async {
    final http.Response resp;
    try {
      resp = await _client.get(location).timeout(httpTimeout);
    } catch (e) {
      throw NasneError.unreachable('ssdp:describe', cause: e);
    }
    if (resp.statusCode != 200) {
      throw NasneError.http(resp.statusCode, 'ssdp:describe');
    }
    return parseDeviceDescription(
        utf8.decode(resp.bodyBytes, allowMalformed: true), location);
  }
}

/// Parses a UPnP device description document into a [NasneDevice].
/// Exposed for fixture tests; [location] is the URL the document was
/// fetched from and the base for resolving relative control URLs.
NasneDevice parseDeviceDescription(String xmlText, Uri location) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlText);
  } catch (e) {
    throw NasneError.parse('ssdp:describe', cause: e);
  }
  final deviceElement = firstDescendant(doc.rootElement, 'device');
  if (deviceElement == null) {
    throw NasneError.parse('ssdp:describe', cause: 'no <device> element');
  }
  String text(String name) => childText(deviceElement, name) ?? '';

  final services = <String, UpnpServiceInfo>{};
  final serviceList = firstChild(deviceElement, 'serviceList');
  if (serviceList != null) {
    for (final service in childElements(serviceList, 'service')) {
      final type = childText(service, 'serviceType');
      final control = childText(service, 'controlURL');
      if (type == null || control == null) continue;
      Uri? resolve(String? value) =>
          value == null ? null : location.resolve(value);
      services[type] = UpnpServiceInfo(
        serviceType: type,
        controlUrl: location.resolve(control),
        scpdUrl: resolve(childText(service, 'SCPDURL')),
        eventSubUrl: resolve(childText(service, 'eventSubURL')),
      );
    }
  }

  return NasneDevice(
    host: location.host,
    descriptionUrl: location,
    friendlyName: text('friendlyName'),
    modelName: text('modelName'),
    manufacturer: text('manufacturer'),
    udn: text('UDN'),
    services: services,
  );
}
