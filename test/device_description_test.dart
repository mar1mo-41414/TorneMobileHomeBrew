/// Device description parsing against the masked phase 0 fixture.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

void main() {
  test('description identifies a nasne and resolves control URLs', () {
    final xml = File('test/fixtures/upnp_description.xml').readAsStringSync();
    final device = parseDeviceDescription(
        xml, Uri.parse('http://192.0.2.1:58888/'));

    expect(device.isNasne, isTrue);
    expect(device.friendlyName, 'nasne');
    expect(device.modelName, 'nasne');
    expect(device.host, '192.0.2.1');
    expect(
      device.controlUrl(
          'urn:schemas-xsrs-org:service:X_ScheduledRecording:2'),
      Uri.parse('http://192.0.2.1:64230/XSRS'),
    );
    expect(
      device.controlUrl('urn:schemas-upnp-org:service:ContentDirectory:1'),
      Uri.parse('http://192.0.2.1:58888/MediaServer_ContentDirectory/control'),
    );
    expect(
      device.controlUrl('urn:schemas-s-bras-org:service:X_PvrControl:1'),
      Uri.parse('http://192.0.2.1:64230/X_PvrControl'),
    );
  });

  test('direct (manual) device exposes the measured fallback URLs', () {
    final device = NasneDevice.direct('192.0.2.9');
    expect(
      device.controlUrl(
          'urn:schemas-xsrs-org:service:X_ScheduledRecording:2'),
      Uri.parse('http://192.0.2.9:64230/XSRS'),
    );
    expect(
      device.controlUrl('urn:schemas-upnp-org:service:ContentDirectory:1'),
      Uri.parse('http://192.0.2.9:58888/MediaServer_ContentDirectory/control'),
    );
  });
}
