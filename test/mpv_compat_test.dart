/// Legacy sync mpv init decision (plan 139): on Android at
/// API 28 or below, media_kit's async initialization can wait
/// forever for an event reply, so the player is created with
/// the synchronous property path there. These tests pin the
/// decision's boundaries — the API line, the Android gate and
/// the unknown-SDK fallback — and that the wakeup kick is a
/// safe no-op off Android. The design lives in
/// app/mpv_compat.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/mpv_compat.dart';

void main() {
  group('shouldUseLegacySyncMpvInit', () {
    test('the boundary is API 28', () {
      expect(legacySyncMpvInitMaxSdkInt, 28);
    });

    test('Android at API 28 or below is legacy', () {
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: true, androidSdkInt: 28),
        isTrue,
      );
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: true, androidSdkInt: 24),
        isTrue,
      );
      // The TV flavor's floor (plan 121): the oldest devices
      // the app still installs on are on the legacy path.
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: true, androidSdkInt: 21),
        isTrue,
      );
    });

    test('Android at API 29 or above keeps the async default', () {
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: true, androidSdkInt: 29),
        isFalse,
      );
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: true, androidSdkInt: 35),
        isFalse,
      );
    });

    test('an unknown SDK int is not legacy', () {
      // The platform did not answer: the async default is the
      // behaviour every current install runs, and only a
      // positively known old device changes it.
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: true, androidSdkInt: null),
        isFalse,
      );
    });

    test('non-Android is never legacy, whatever the value', () {
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: false, androidSdkInt: 28),
        isFalse,
      );
      expect(
        shouldUseLegacySyncMpvInit(isAndroid: false, androidSdkInt: null),
        isFalse,
      );
    });
  });

  group('kickMpvEventLoop', () {
    test('off Android it is a no-op that reports false', () {
      // The test host is not Android: the kick must not touch
      // FFI at all (there is no player behind the handle).
      expect(kickMpvEventLoop(0), isFalse);
    });
  });
}
