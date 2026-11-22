/// App variant (TV flavor): the variant reaches the provider
/// container from the entry point through the bootstrap, and the
/// TV edition's starting playback quality is the mobile
/// transcode until the user stores a choice of their own.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/bootstrap.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/core/core.dart';

/// Lets the notifier's asynchronous restore settle.
Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('appVariantProvider', () {
    test('defaults to the standard edition', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appVariantProvider), AppVariant.standard);
    });

    test('fileStoreContainer carries the entry point variant', () async {
      final dir = await Directory.systemTemp.createTemp();
      addTearDown(() => dir.delete(recursive: true));
      final container = fileStoreContainer(dir, variant: AppVariant.tv);
      addTearDown(container.dispose);
      expect(container.read(appVariantProvider), AppVariant.tv);
    });
  });

  group('playback quality starting value per variant', () {
    late InMemoryKeyValueStore keyValues;

    setUp(() {
      keyValues = InMemoryKeyValueStore();
    });

    ProviderContainer makeContainer(AppVariant variant) {
      final container = ProviderContainer(
        overrides: [
          appVariantProvider.overrideWithValue(variant),
          keyValueStoreProvider.overrideWithValue(keyValues),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('TV with nothing stored starts from the mobile transcode', () async {
      final container = makeContainer(AppVariant.tv);
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isTrue);
    });

    test('TV restores a stored original choice', () async {
      await keyValues.write('playback_use_mobile', 'false');
      final container = makeContainer(AppVariant.tv);
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isFalse);
    });

    test('standard with nothing stored starts from the original', () async {
      final container = makeContainer(AppVariant.standard);
      container.read(playbackQualityProvider);
      await flush();
      expect(container.read(playbackQualityProvider), isFalse);
    });
  });
}
