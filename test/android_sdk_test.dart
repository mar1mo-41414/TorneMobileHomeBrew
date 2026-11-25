/// Android SDK int supply (plan 139): the value is read from
/// the platform side once at startup and handed to the
/// provider container as an override, the route the player
/// screen's mpv init branch reads. These tests pin the
/// reader's failure folding (any platform failure is null —
/// the safe side) and the bootstrap override. The design
/// lives in app/android_sdk.dart and app/mpv_compat.dart.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/android_sdk.dart';
import 'package:tmhb/app/bootstrap.dart';
import 'package:tmhb/app/providers.dart';

void main() {
  group('AndroidSdkIntReader', () {
    test('returns the platform value', () async {
      final reader = AndroidSdkIntReader(platformRead: () async => 28);
      expect(await reader.read(), 28);
    });

    test('a platform failure folds into null', () async {
      final reader = AndroidSdkIntReader(
        platformRead: () async => throw StateError('no channel'),
      );
      expect(await reader.read(), isNull);
    });

    test('a platform null stays null', () async {
      final reader = AndroidSdkIntReader(platformRead: () async => null);
      expect(await reader.read(), isNull);
    });
  });

  group('androidSdkIntProvider', () {
    test('the plain default is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(androidSdkIntProvider), isNull);
    });

    test('fileStoreContainer hands the startup value in', () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_sdk');
      addTearDown(() => dir.delete(recursive: true));
      final container = fileStoreContainer(dir, androidSdkInt: 28);
      addTearDown(container.dispose);
      expect(container.read(androidSdkIntProvider), 28);
    });

    test('fileStoreContainer without a value keeps null', () async {
      final dir = await Directory.systemTemp.createTemp('tmhb_sdk');
      addTearDown(() => dir.delete(recursive: true));
      final container = fileStoreContainer(dir);
      addTearDown(container.dispose);
      expect(container.read(androidSdkIntProvider), isNull);
    });
  });
}
