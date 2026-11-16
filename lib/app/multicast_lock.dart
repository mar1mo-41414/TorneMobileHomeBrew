/// Android MulticastLock guard (plan 17): holds a WifiManager
/// MulticastLock via a platform channel while SSDP search runs, so
/// M-SEARCH responses are not filtered by the Wi-Fi driver.
///
/// Best-effort by design: on non-Android platforms, and whenever the
/// channel is unavailable (e.g. widget tests), the calls are no-ops
/// and discovery proceeds (the subnet scan remains as fallback).
library;

import 'dart:io';

import 'package:flutter/services.dart';

import '../core/core.dart';

class MethodChannelMulticastLockGuard implements MulticastLockGuard {
  MethodChannelMulticastLockGuard({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'com.markun.tmhb/multicast_lock';

  final MethodChannel _channel;

  @override
  Future<void> acquire() => _invoke('acquire');

  @override
  Future<void> release() => _invoke('release');

  Future<void> _invoke(String method) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // Locking is an optimisation for SSDP reception; never let it
      // break discovery itself.
    }
  }
}
