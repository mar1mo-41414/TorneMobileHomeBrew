/// torne mobile HomeBrew edition — app entry point.
///
/// Before the first frame, the local stores are backed by JSON files
/// in the app store directory so registrations and caches
/// survive restarts (app/store_directory.dart, app/bootstrap.dart).
/// The UI is the v1 screen set
/// of plan 5.6, built on the phase 1 core through the composition
/// root (app/providers.dart) and app state (app/state.dart).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
// Flutter 3.50 deprecates package:flutter/material.dart in favour of
// package:material_ui/material_ui.dart (the scaffold's own import).
import 'package:material_ui/material_ui.dart';

import 'app/android_sdk.dart';
import 'app/bootstrap.dart';
import 'app/variant.dart';
import 'core/diagnostics.dart';
import 'ui/widgets.dart';
import 'app/lifecycle_log.dart';
import 'app/providers.dart';
import 'app/store_directory.dart';
import 'ui/app_shell.dart';

Future<void> main() => runTmhbApp(AppVariant.standard);

/// Shared startup for every entry point: lib/main.dart runs the
/// standard edition, lib/main_tv.dart the TV edition. Only the
/// [variant] differs; the stores, the migration and the app
/// widget are the same code either way.
Future<void> runTmhbApp(AppVariant variant) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final storeDirectory = await resolveStoreDirectory();
  // Split the legacy shared key-value file into per-purpose
  // files before anything reads the stores (plan 96).
  await migrateLegacyKeyValueFiles(storeDirectory);
  // The Android SDK int is read before the container
  // exists: the bootstrap hands it in as an override, and
  // the player screen branches the mpv initialization on it
  // (plan 139). Null off Android and whenever the platform
  // does not answer — the safe side everywhere it is read.
  final androidSdkInt = await AndroidSdkIntReader().read();
  final container = fileStoreContainer(
    storeDirectory,
    variant: variant,
    androidSdkInt: androidSdkInt,
  );
  // App lifecycle transitions go to the debug log (plan 36), so a
  // field log shows when the process was suspended and resumed
  // around a playback session (the wakelock sleep investigation).
  // The binding holds the observer for the app's lifetime.
  final diagLog = container.read(diagLogProvider);
  LifecycleLogger(diagLog).attach();
  // Which edition this process is goes into the diagnostics log
  // at startup: the variant is chosen only by the Dart entry
  // point, and a TV package built from the standard entry point
  // runs with every TV behaviour silently inert (plan 133), so
  // a field log has to be able to identify such a build.
  diagLog(DiagCategory.playback, 'app started: variant ${variant.name}');
  runApp(
    UncontrolledProviderScope(container: container, child: const TmhbApp()),
  );
}

class TmhbApp extends StatelessWidget {
  const TmhbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'torne mobile HB',
      // A tap outside a text field dismisses the keyboard
      // anywhere in the app (plan 54).
      builder: (context, child) =>
          KeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const AppShell(),
    );
  }
}
