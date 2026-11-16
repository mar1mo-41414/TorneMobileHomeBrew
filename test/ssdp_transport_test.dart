/// SSDP transport MulticastLock hook (plan 17): the guard is held
/// for the duration of a search, and the platform-channel guard is
/// a no-op off Android.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/multicast_lock.dart';
import 'package:tmhb/core/core.dart';

class _RecordingGuard implements MulticastLockGuard {
  final List<String> calls = [];

  @override
  Future<void> acquire() async => calls.add('acquire');

  @override
  Future<void> release() async => calls.add('release');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('search holds the multicast lock guard around the exchange',
      () async {
    final guard = _RecordingGuard();
    final transport = SsdpTransport(lockGuard: guard);
    // The result depends on the network the test runs on (a real
    // nasne may answer); only the guard contract is asserted.
    await transport.search(
      SsdpDiscoveryService.mediaServerSearchTarget,
      timeout: const Duration(milliseconds: 300),
    );
    expect(guard.calls, ['acquire', 'release']);
  });

  test('search without a guard completes', () async {
    const transport = SsdpTransport();
    await transport.search(
      SsdpDiscoveryService.mediaServerSearchTarget,
      timeout: const Duration(milliseconds: 300),
    );
  });

  test('method-channel guard does not call the channel off Android',
      () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('com.markun.tmhb/multicast_lock');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final guard = MethodChannelMulticastLockGuard(channel: channel);
    await guard.acquire();
    await guard.release();
    // The test host is not Android, so both must be no-ops.
    expect(calls, isEmpty);
  });
}
