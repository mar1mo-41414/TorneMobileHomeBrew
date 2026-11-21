/// Regression tests for the shared-file write race (plan 96):
/// several writers share one JSON file through read-modify-write,
/// and before the fix an overlapping write silently dropped the
/// other writers' keys — the selected device reverted to the
/// first registration, settings vanished, and a read that caught
/// a file mid-write treated it as empty and wiped everything.
///
/// These tests use the real file-backed stores on a real file
/// system, with a large pre-existing value in the file to widen
/// the read-modify-write window, like the 8-day programme-guide
/// cache does in the field.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('JsonFileKeyValueStore under concurrent writers', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tmhb_kv_race');
      file = File('${dir.path}/key_values.json');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('concurrent writes of different keys all survive', () async {
      final store = JsonFileKeyValueStore(file);
      // A large pre-existing value (the programme-guide cache is
      // the field case) makes every read-modify-write slow, which
      // is exactly when the writers used to overlap.
      await store.write('big', 'x' * 256 * 1024);

      for (var round = 0; round < 3; round++) {
        final keys = [for (var i = 0; i < 8; i++) 'round${round}_key$i'];
        await Future.wait([for (final k in keys) store.write(k, 'value-$k')]);
        for (final k in keys) {
          expect(await store.read(k), 'value-$k', reason: '$k was lost');
        }
      }
      expect((await store.read('big'))!.length, 256 * 1024);
    });

    test('a selection write racing a huge cache write survives', () async {
      final store = JsonFileKeyValueStore(file);
      await store.write('epg-guide:192.0.2.1:2', 'y' * 512 * 1024);
      await Future.wait([
        store.write('selected_host', '192.0.2.2'),
        store.write('epg-guide:192.0.2.1:2', 'z' * 512 * 1024),
        store.write('epg_show_subchannels', 'true'),
      ]);
      expect(await store.read('selected_host'), '192.0.2.2');
      expect(await store.read('epg_show_subchannels'), 'true');
      expect((await store.read('epg-guide:192.0.2.1:2'))!.length, 512 * 1024);
    });

    test('concurrent write and delete of different keys both apply', () async {
      final store = JsonFileKeyValueStore(file);
      await store.write('big', 'x' * 128 * 1024);
      await store.write('doomed', 'gone');
      await Future.wait([store.write('kept', 'yes'), store.delete('doomed')]);
      expect(await store.read('kept'), 'yes');
      expect(await store.read('doomed'), isNull);
      expect((await store.read('big'))!.length, 128 * 1024);
    });

    test('no torn or leftover state: the file always parses', () async {
      final store = JsonFileKeyValueStore(file);
      await Future.wait([
        for (var i = 0; i < 16; i++) store.write('k$i', 'v' * 4096),
      ]);
      final decoded = jsonDecode(await file.readAsString());
      expect(decoded, isA<Map>());
      expect((decoded as Map).length, 16);
    });

    test('a corrupt file is preserved aside, never silently wiped', () async {
      await file.writeAsString('{"selected_host": "192.0.2.');
      final store = JsonFileKeyValueStore(file);
      expect(await store.read('selected_host'), isNull);
      await store.write('selected_host', '192.0.2.9');
      expect(await store.read('selected_host'), '192.0.2.9');
      // The corrupt original is still on disk under a side name.
      final names = [for (final e in dir.listSync()) e.uri.pathSegments.last];
      expect(
        names.any((n) => n.contains('corrupt')),
        isTrue,
        reason: 'directory contains: $names',
      );
    });
  });

  group('JsonFileRegistrationStore under concurrent writers', () {
    late Directory dir;
    late File file;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tmhb_reg_race');
      file = File('${dir.path}/registrations.json');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    RegisteredNasne reg(int n) => RegisteredNasne(
      host: '192.0.2.$n',
      udn: 'uuid:00000000-0000-1000-8000-0011223344${50 + n}',
      friendlyName: 'nasne $n',
      macAddr: '00:11:22:33:44:${50 + n}',
    );

    test('concurrent saves all survive', () async {
      final store = JsonFileRegistrationStore(file);
      await Future.wait([for (var i = 1; i <= 6; i++) store.save(reg(i))]);
      final all = await store.loadAll();
      expect(all.map((d) => d.host).toSet(), {
        for (var i = 1; i <= 6; i++) '192.0.2.$i',
      });
    });

    test('a remove racing saves of other devices applies cleanly', () async {
      final store = JsonFileRegistrationStore(file);
      await store.save(reg(9));
      await Future.wait([
        store.remove('192.0.2.9'),
        store.save(reg(1)),
        store.save(reg(2)),
      ]);
      final hosts = (await store.loadAll()).map((d) => d.host).toSet();
      expect(hosts, {'192.0.2.1', '192.0.2.2'});
    });
  });
}
