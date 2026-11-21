/// The plan 96 split migration: an existing install has every
/// key in the legacy key_values.json — the device selection and
/// settings next to the channel cache, the programme-guide
/// cache and the DTCP SRM. The first launch with the split
/// stores must move the cache and SRM keys to their own files
/// (copy, verify, then clean) without losing settings or the
/// selection, and must leave the legacy data in place when a
/// copy cannot be verified.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/bootstrap.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';

const regA = RegisteredNasne(
  host: '192.0.2.1',
  udn: 'uuid:00000000-0000-1000-8000-001122334455',
  friendlyName: 'nasne A',
  macAddr: '00:11:22:33:44:55',
);

const regB = RegisteredNasne(
  host: '192.0.2.2',
  udn: 'uuid:00000000-0000-1000-8000-001122334466',
  friendlyName: 'nasne B',
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
  group('migrateLegacyKeyValueFiles', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tmhb_migration');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    File file(String name) => File('${dir.path}/$name');

    Future<Map<String, dynamic>> jsonOf(File f) async =>
        (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();

    /// A pre-split install: two registrations, and one shared
    /// key_values.json holding the selection, settings, both
    /// caches and the SRM — written through the same cache
    /// classes the old app used, so the payloads are genuine.
    Future<void> seedLegacyInstall() async {
      final registrations = JsonFileRegistrationStore(
        file(registrationFileName),
      );
      await registrations.save(regA);
      await registrations.save(regB);
      final legacy = JsonFileKeyValueStore(file(keyValueFileName));
      await legacy.write('selected_host', regB.host);
      await legacy.write('epg_show_subchannels', 'true');
      await legacy.write('unknown_future_key', 'keep-me');
      await ChannelCache(legacy).save(regB.host, 2, channels);
      await EpgGuideCache(
        legacy,
      ).save(regB.host, 2, const EpgGuide(broadcastingType: 2, services: []));
      await legacy.write(KeyValueSrmStore.storageKey, 'aabbcc');
    }

    test('caches and SRM move out; settings and selection stay', () async {
      await seedLegacyInstall();
      await migrateLegacyKeyValueFiles(dir);

      final legacy = await jsonOf(file(keyValueFileName));
      expect(
        legacy.keys,
        containsAll([
          'selected_host',
          'epg_show_subchannels',
          'unknown_future_key',
        ]),
      );
      expect(
        legacy.keys.any((k) => k.startsWith(ChannelCache.keyPrefix)),
        isFalse,
      );
      expect(
        legacy.keys.any((k) => k.startsWith(EpgGuideCache.keyPrefix)),
        isFalse,
      );
      expect(legacy.containsKey(KeyValueSrmStore.storageKey), isFalse);

      final channelFile = await jsonOf(file(channelCacheFileName));
      expect(channelFile.keys, ['channels:${regB.host}:2']);
      final epgFile = await jsonOf(file(epgCacheFileName));
      expect(epgFile.keys, ['epg-guide:${regB.host}:2']);
      final srmFile = await jsonOf(file(srmFileName));
      expect(srmFile, {KeyValueSrmStore.storageKey: 'aabbcc'});

      // And the split container actually reads everything back:
      // the cached channels, the SRM bytes, and the selection.
      final container = fileStoreContainer(dir);
      addTearDown(container.dispose);
      final cached = await container
          .read(channelCacheProvider)
          .load(regB.host, 2);
      expect(cached, isNotNull);
      expect(cached!.single.serviceName, 'テスト放送');
      expect(await container.read(srmStoreProvider).loadRaw(), [
        0xaa,
        0xbb,
        0xcc,
      ]);
      await container.read(registrationsProvider.future);
      // The persisted selection is restored asynchronously.
      for (var i = 0; i < 100; i++) {
        if (container.read(selectedHostProvider) == regB.host) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(container.read(selectedRegistrationProvider)?.host, regB.host);
    });

    test('running it again changes nothing', () async {
      await seedLegacyInstall();
      await migrateLegacyKeyValueFiles(dir);
      final before = {
        for (final name in [
          keyValueFileName,
          channelCacheFileName,
          epgCacheFileName,
          srmFileName,
        ])
          name: await file(name).readAsString(),
      };
      await migrateLegacyKeyValueFiles(dir);
      for (final entry in before.entries) {
        expect(
          await file(entry.key).readAsString(),
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('an unwritable target leaves the legacy keys in place', () async {
      await seedLegacyInstall();
      // A directory where the channel cache file should be:
      // every write to it fails, so its keys must stay legacy.
      await Directory('${dir.path}/$channelCacheFileName').create();
      await migrateLegacyKeyValueFiles(dir);

      final legacy = await jsonOf(file(keyValueFileName));
      expect(
        legacy.keys.any((k) => k.startsWith(ChannelCache.keyPrefix)),
        isTrue,
      );
      // The other stores still migrated, and settings never move.
      expect(
        legacy.keys.any((k) => k.startsWith(EpgGuideCache.keyPrefix)),
        isFalse,
      );
      expect(legacy.containsKey(KeyValueSrmStore.storageKey), isFalse);
      expect(legacy['selected_host'], regB.host);
    });

    test('a fresh install (no legacy file) is a no-op', () async {
      await migrateLegacyKeyValueFiles(dir);
      expect(await file(keyValueFileName).exists(), isFalse);
      final container = fileStoreContainer(dir);
      addTearDown(container.dispose);
      await container
          .read(keyValueStoreProvider)
          .write('selected_host', regA.host);
      expect(await jsonOf(file(keyValueFileName)), {
        'selected_host': regA.host,
      });
    });
  });
}
