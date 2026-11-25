/// The device's Android SDK int (plan 139).
///
/// One consumer must branch on the Android generation before
/// any UI exists: the player creation in the player screen
/// (see app/mpv_compat.dart). Dart has no API for the SDK int,
/// so the value is read from the platform side once at
/// startup and rides the provider container as an override
/// (app/bootstrap.dart), the same route as the app variant.
///
/// The platform method rides the existing credential-downloads
/// channel: MainActivity already hosts that channel for the
/// Downloads scan (plan 127), and one integer does not warrant
/// a channel of its own. Off Android — and whenever the
/// platform side does not answer, e.g. a native build
/// predating the method — the answer is null, which every
/// consumer reads as "not a positively known old device", the
/// safe side (see mpv_compat.dart).
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// The platform call behind [AndroidSdkIntReader]: the SDK
/// int, or null when the platform does not provide one.
typedef PlatformAndroidSdkInt = Future<int?> Function();

/// Reads the device's Android SDK int from the platform side.
class AndroidSdkIntReader {
  AndroidSdkIntReader({PlatformAndroidSdkInt? platformRead})
    : _platformRead = platformRead ?? _platformSdkInt;

  final PlatformAndroidSdkInt _platformRead;

  static const MethodChannel _channel = MethodChannel(
    'com.markun.tmhb/credential_downloads',
  );

  static Future<int?> _platformSdkInt() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<int>('getAndroidSdkInt');
  }

  /// The SDK int, or null per the library comment. Platform
  /// failures fold into null here: the value steers a
  /// compatibility branch, so a failed read must fall back to
  /// the default behaviour, never break startup.
  Future<int?> read() async {
    try {
      return await _platformRead();
    } catch (_) {
      return null;
    }
  }
}
