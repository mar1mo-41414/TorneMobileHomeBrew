/// App bootstrap (phase 2): builds the provider container whose
/// local stores are backed by JSON files, so registrations and
/// caches survive app restarts. [main] resolves the application
/// documents directory via path_provider and hands it here; tests
/// pass a temporary directory instead.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'providers.dart';

/// File names used inside the documents directory.
const registrationFileName = 'registrations.json';
const keyValueFileName = 'key_values.json';

/// A [ProviderContainer] with [registrationStoreProvider] and
/// [keyValueStoreProvider] — and therefore the channel cache —
/// wired to JSON files inside [documentsDirectory], instead of the
/// in-memory defaults.
ProviderContainer fileStoreContainer(Directory documentsDirectory) {
  return ProviderContainer(
    overrides: [
      registrationStoreProvider.overrideWithValue(
        JsonFileRegistrationStore(
          File('${documentsDirectory.path}/$registrationFileName'),
        ),
      ),
      keyValueStoreProvider.overrideWithValue(
        JsonFileKeyValueStore(
          File('${documentsDirectory.path}/$keyValueFileName'),
        ),
      ),
    ],
  );
}
