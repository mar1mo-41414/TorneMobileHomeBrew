/// Phase 2 wiring proof: the container built by fileStoreContainer
/// (the one main() installs) persists registrations and the channel
/// cache as JSON files, so a fresh container — an app restart —
/// reads back what a previous one wrote.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/bootstrap.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';

const reg = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:00000000-0000-1000-8000-001122334455',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

const regB = RegisteredNasne(
  host: '192.0.2.2',
  udn: 'uuid:00000000-0000-1000-8000-001122334466',
  friendlyName: 'nasne (2台目)',
  macAddr: '00:11:22:33:44:66',
);

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

void main() {
  group('fileStoreContainer', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tmhb_bootstrap');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('stores are file-backed, not the in-memory defaults', () {
      final container = fileStoreContainer(dir);
      addTearDown(container.dispose);
      expect(container.read(registrationStoreProvider),
          isA<JsonFileRegistrationStore>());
      expect(
          container.read(keyValueStoreProvider), isA<JsonFileKeyValueStore>());
    });

    test('registrations and channel cache survive a restart', () async {
      final first = fileStoreContainer(dir);
      await first.read(registrationStoreProvider).save(reg);
      await first.read(channelCacheProvider).save('192.0.2.1', 2, channels);
      first.dispose();

      // Both JSON files were created inside the given directory.
      expect(File('${dir.path}/$registrationFileName').existsSync(), isTrue);
      expect(File('${dir.path}/$keyValueFileName').existsSync(), isTrue);

      final second = fileStoreContainer(dir);
      addTearDown(second.dispose);
      final loaded = await second.read(registrationStoreProvider).loadAll();
      expect(loaded.single.host, '192.0.2.1');
      expect(loaded.single.pin, '334455');
      final cached =
          await second.read(channelCacheProvider).load('192.0.2.1', 2);
      expect(cached, isNotNull);
      expect(cached!.single.serviceName, 'テスト放送');
    });

    test('selected device survives a restart', () async {
      final first = fileStoreContainer(dir);
      final store = first.read(registrationStoreProvider);
      await store.save(reg);
      await store.save(regB);
      first.read(selectedHostProvider.notifier).select(regB.host);
      // The selection write-back is asynchronous; wait until it
      // lands in the key-value file before simulating the restart.
      final kvFile = File('${dir.path}/$keyValueFileName');
      for (var i = 0; i < 100; i++) {
        if (await kvFile.exists() &&
            (await kvFile.readAsString()).contains(regB.host)) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      first.dispose();

      final second = fileStoreContainer(dir);
      addTearDown(second.dispose);
      await second.read(registrationsProvider.future);
      // The persisted selection is restored asynchronously.
      for (var i = 0; i < 100; i++) {
        if (second.read(selectedHostProvider) == regB.host) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(second.read(selectedHostProvider), regB.host);
      expect(second.read(selectedRegistrationProvider)?.host, regB.host);
    });
  });
}
