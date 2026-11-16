/// Composition-root swap proof (plan 12.9 step 5): the providers can
/// be overridden with mock implementations of the domain interfaces,
/// and consumers receive the mocks without any other change.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';

class _FakeDiscovery implements DiscoveryService {
  @override
  Future<List<NasneDevice>> discover({Duration? timeout}) async =>
      [NasneDevice.direct('192.0.2.99')];

  @override
  Future<NasneDevice> describe(Uri location) async =>
      NasneDevice.direct('192.0.2.99');
}

class _FakeRegistration implements RegistrationService {
  @override
  Future<RegisteredNasne> register(NasneDevice device) async =>
      const RegisteredNasne(
        host: '192.0.2.99',
        udn: 'uuid:fake',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );

  @override
  Future<bool> verify(RegisteredNasne device) async => true;
}

void main() {
  test('interface providers swap to mocks via overrides', () async {
    final container = ProviderContainer(overrides: [
      discoveryServiceProvider.overrideWithValue(_FakeDiscovery()),
      registrationServiceProvider.overrideWithValue(_FakeRegistration()),
      registrationStoreProvider
          .overrideWithValue(InMemoryRegistrationStore()),
    ]);
    addTearDown(container.dispose);

    final discovery = container.read(discoveryServiceProvider);
    expect(discovery, isA<_FakeDiscovery>());
    final found = await discovery.discover();
    expect(found.single.host, '192.0.2.99');

    final registration = container.read(registrationServiceProvider);
    final reg = await registration.register(found.single);
    expect(reg.udn, 'uuid:fake');
    expect(await registration.verify(reg), isTrue);

    // The store provider is swappable the same way.
    final store = container.read(registrationStoreProvider);
    await store.save(reg);
    expect((await store.loadAll()).single.host, '192.0.2.99');
  });

  test('default graph assembles per-device services from a registration',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const reg = RegisteredNasne(
      host: '192.0.2.1',
      udn: 'uuid:x',
      friendlyName: 'nasne',
      macAddr: '00:11:22:33:44:55',
    );
    final services = container.read(deviceServicesProvider(reg));
    expect(services.deviceInfo, isA<WebApiDeviceInfoService>());
    expect(services.schedules, isA<SoapScheduleService>());
    expect(services.titles, isA<SoapTitleCatalogService>());
    expect(services.metadata, isA<DlnaMetadataService>());
    expect(services.playback.isSupported, isFalse);
  });
}
