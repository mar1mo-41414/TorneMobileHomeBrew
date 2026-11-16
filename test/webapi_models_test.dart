/// Model parsers against the masked phase 0 WebAPI fixtures.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

Map<String, dynamic> fixtureJson(String name) {
  final file = File('test/fixtures/webapi/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('NetworkInfo + PIN derivation', () {
    test('parses the fixture; PIN derives from the masked MAC', () {
      final net = NetworkInfo.fromJson(fixtureJson('status_networkIfInfoGet.json'));
      expect(net.macAddr, '00:11:22:33:44:55');
      expect(net.ipv4Addr, '192.0.2.1');
      expect(TokenProvider.derivePin(net.macAddr), '334455');
    });
  });

  group('HDD models', () {
    test('HDDListGet entries', () {
      final json = fixtureJson('status_HDDListGet.json');
      final entries = [
        for (final e in json['HDD'] as List)
          HddEntry.fromJson((e as Map).cast<String, dynamic>()),
      ];
      expect(entries, isNotEmpty);
      expect(entries.first.id, 0);
    });

    test('HDDInfoGet detail (sizes are bytes, serial masked)', () {
      final json = fixtureJson('status_HDDInfoGet_id0.json');
      final info = HddInfo.fromJson(
          (json['HDD'] as Map).cast<String, dynamic>());
      expect(info.totalBytes, 498521100288);
      expect(info.freeBytes, 496123510784);
      expect(info.serialNumber, 'SERIAL0000');
      expect(info.format, 'xfs');
    });
  });

  group('Channel list', () {
    test('24 terrestrial channels; serviceId renders as xsrs hex', () {
      final json =
          fixtureJson('status_channelListGet_broadcastingType2.json');
      final channels = [
        for (final e in json['channel'] as List)
          Channel.fromJson((e as Map).cast<String, dynamic>(),
              broadcastingType: 2),
      ];
      expect(channels.length, 24);
      expect(channels.first.serviceId, 56832);
      expect(channels.first.serviceIdHex, '0xde00');
      expect(channels.first.networkId, 30848);
    });
  });

  group('LiveStatus aggregate', () {
    test('sections carry generations; EIT_PF unpopulated in fixture', () {
      final live =
          LiveStatus.fromJson(fixtureJson('status_liveStreamStatusListGet.json'));
      expect(live.sections.length, 29);
      expect(live.section('EIT_PF')?.generation, 0);
      expect(live.eitPf.populated, isFalse);
      expect(live.caMessages, isEmpty);
      expect(live.section('recNgList')?.generation, 1);
    });
  });

  group('RecNg items', () {
    test('standalone endpoint items parse (titles masked)', () {
      final json = fixtureJson('status_recNgListGet.json');
      final items = [
        for (final e in json['item'] as List)
          RecNgItem.fromJson((e as Map).cast<String, dynamic>()),
      ];
      expect(items.length, json['number']);
      expect(items.first.title, 'テスト番組タイトル');
      expect(items.first.id, '10000000000000000009');
      expect(items.first.serviceId, 56840);
      expect(items.first.startTime, isNotNull);
    });
  });

  group('Misc reads', () {
    test('box name fixture', () {
      final json = fixtureJson('status_boxNameGet.json');
      expect(json['name'], 'nasne-test');
    });

    test('BcasInfo parses with a masked card id', () {
      final info = BcasInfo.fromJson(fixtureJson('status_BCASInfoGet.json'));
      expect(info.cardId, '00000000000000000000');
    });

    test('ClientInfo parses (requester itself)', () {
      final json = fixtureJson('status_requestClientInfoGet.json');
      final client = ClientInfo.fromJson(
          (json['client'] as Map).cast<String, dynamic>());
      expect(client.name, 'test-client');
      expect(client.macAddr, '00:11:22:33:44:55');
    });

    test('counts', () {
      expect(
          fixtureJson('recorded_recordedContentCountGet.json')['count'], 2);
      expect(
          fixtureJson('recorded_recordedContentMaxCountGet.json')['count'],
          3000);
    });
  });
}
