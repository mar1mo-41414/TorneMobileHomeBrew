/// App bootstrap (phase 2): builds the provider container whose
/// local stores are backed by JSON files, so registrations and
/// caches survive app restarts. [main] resolves the store
/// directory (app/store_directory.dart: documents on mobile,
/// application support on desktop) and hands it here; tests pass
/// a temporary directory instead.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'providers.dart';

/// File and directory names used inside the store directory.
const registrationFileName = 'registrations.json';
const keyValueFileName = 'key_values.json';
const debugLogsDirectoryName = 'debug_logs';

/// A [ProviderContainer] with [registrationStoreProvider] and
/// [keyValueStoreProvider] — and therefore the channel cache —
/// wired to JSON files inside [storeDirectory], instead of the
/// in-memory defaults.
ProviderContainer fileStoreContainer(Directory storeDirectory) {
  return ProviderContainer(
    overrides: [
      registrationStoreProvider.overrideWithValue(
        JsonFileRegistrationStore(
          File('${storeDirectory.path}/$registrationFileName'),
        ),
      ),
      keyValueStoreProvider.overrideWithValue(
        JsonFileKeyValueStore(
          File('${storeDirectory.path}/$keyValueFileName'),
        ),
      ),
      storeDirectoryProvider.overrideWithValue(storeDirectory),
    ],
  );
}
