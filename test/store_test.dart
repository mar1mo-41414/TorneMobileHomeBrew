/// Persistence: registration store + channel cache round-trips.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

const reg1 = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:00000000-0000-1000-8000-001122334455',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);
const reg2 = RegisteredNasne(
  host: '192.0.2.2',
  udn: 'uuid:11111111-0000-1000-8000-001122334455',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:66',
);

void main() {
  group('InMemoryRegistrationStore', () {
    test('save / replace by host / remove', () async {
      final store = InMemoryRegistrationStore();
      await store.save(reg1);
      await store.save(reg2);
      expect((await store.loadAll()).length, 2);
      await store.save(const RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:replaced',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      ));
      final all = await store.loadAll();
      expect(all.length, 2);
      expect(all.firstWhere((d) => d.host == '192.0.2.1').udn,
          'uuid:replaced');
      await store.remove('192.0.2.1');
      expect((await store.loadAll()).map((d) => d.host), ['192.0.2.2']);
    });
  });

  group('JsonFileRegistrationStore', () {
    test('persists across instances; PIN re-derives from the MAC',
        () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_store');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/registrations.json');

      final store = JsonFileRegistrationStore(file);
      expect(await store.loadAll(), isEmpty);
      await store.save(reg1);

      final reopened = JsonFileRegistrationStore(file);
      final loaded = await reopened.loadAll();
      expect(loaded.length, 1);
      expect(loaded.single.host, '192.0.2.1');
      expect(loaded.single.pin, '334455');
    });

    test('a corrupt file reads as empty instead of throwing', () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_store');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/registrations.json');
      await file.writeAsString('not json');
      expect(await JsonFileRegistrationStore(file).loadAll(), isEmpty);
    });
  });

  group('ChannelCache', () {
    test('round-trips channels in WebAPI shape', () async {
      final cache = ChannelCache(InMemoryKeyValueStore());
      expect(await cache.load('192.0.2.1', 2), isNull);
      const channels = [
        Channel(
          broadcastingType: 2,
          networkId: 30848,
          transportStreamId: 30848,
          serviceId: 56832,
          serviceType: 1,
          channelNumber: 31,
          serviceName: 'テスト放送',
          freqChannelNo: '27',
          remoteControlKeyId: 1,
        ),
      ];
      await cache.save('192.0.2.1', 2, channels);
      final loaded = await cache.load('192.0.2.1', 2);
      expect(loaded, isNotNull);
      expect(loaded!.single.serviceId, 56832);
      expect(loaded.single.serviceIdHex, '0xde00');
      expect(loaded.single.serviceName, 'テスト放送');
      // A different broadcasting type is a different cache entry.
      expect(await cache.load('192.0.2.1', 1), isNull);
    });
  });
}
