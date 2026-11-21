/// Persistence of the selected device (SelectedHostNotifier):
/// the choice is written to the key-value store, restored on
/// startup, cleared on deselect, and ignored when the device is
/// no longer registered.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Lets the notifier's asynchronous restore / write-back settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('SelectedHostNotifier persistence', () {
    late InMemoryRegistrationStore registrations;
    late InMemoryKeyValueStore keyValues;

    setUp(() {
      registrations = InMemoryRegistrationStore();
      keyValues = InMemoryKeyValueStore();
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          registrationStoreProvider.overrideWithValue(registrations),
          keyValueStoreProvider.overrideWithValue(keyValues),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('select writes the host to the key-value store', () async {
      final container = makeContainer();
      container.read(selectedHostProvider.notifier).select(regB.host);
      await flush();
      expect(container.read(selectedHostProvider), regB.host);
      expect(await keyValues.read('selected_host'), regB.host);
    });

    test('select(null) deletes the persisted host', () async {
      final container = makeContainer();
      final notifier = container.read(selectedHostProvider.notifier);
      notifier.select(regB.host);
      await flush();
      expect(await keyValues.read('selected_host'), regB.host);
      notifier.select(null);
      await flush();
      expect(container.read(selectedHostProvider), isNull);
      expect(await keyValues.read('selected_host'), isNull);
    });

    test('a fresh container restores the persisted selection', () async {
      final first = makeContainer();
      first.read(selectedHostProvider.notifier).select(regB.host);
      await flush();

      final second = makeContainer();
      second.read(selectedHostProvider);
      await flush();
      expect(second.read(selectedHostProvider), regB.host);
    });

    test('a saved host that is not registered falls back to the first',
        () async {
      await registrations.save(regA);
      await keyValues.write('selected_host', '192.0.2.99');
      final container = makeContainer();
      await container.read(registrationsProvider.future);
      container.read(selectedHostProvider);
      await flush();
      expect(container.read(selectedRegistrationProvider)?.host, regA.host);
    });
  });
}
