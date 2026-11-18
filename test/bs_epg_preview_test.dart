import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/bs_epg_providers.dart';
import 'package:tmhb/core/core.dart';

void main() {
  test('BS EPG uses the measured WebAPI broadcastingType 3', () {
    expect(bsBroadcastingType, 3);
  });

  test('BS service triple can be encoded for EPGGet', () {
    final versionTable = List<int>.filled(12 + 144 + 8, 0);
    // The (network, transport stream, service) triple for a BS service.
    versionTable[12] = 0;
    versionTable[13] = 4;
    versionTable[14] = 0x40;
    versionTable[15] = 0x50;
    versionTable[16] = 0;
    versionTable[17] = 101;
    versionTable[18] = 0xc0;
    versionTable[19] = 0;
    final services = parseEpgVersionServices(versionTable);
    expect(services, [const EpgServiceRef(4, 0x4050, 101)]);
    final body = buildEpgGetBody(services);
    expect(body.length, 32);
    expect(body.sublist(4, 8), [0, 1, 0, 0]);
    expect(body.sublist(8, 16), [0, 4, 0x40, 0x50, 0, 101, 0, 0]);
    expect(body.sublist(16, 32), List<int>.filled(16, 0xff));
  });
}
