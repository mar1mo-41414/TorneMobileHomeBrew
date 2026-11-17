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

import 'app/bootstrap.dart';
import 'ui/widgets.dart';
import 'app/lifecycle_log.dart';
import 'app/providers.dart';
import 'app/store_directory.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final storeDirectory = await resolveStoreDirectory();
  final container = fileStoreContainer(storeDirectory);
  // App lifecycle transitions go to the debug log (plan 36), so a
  // field log shows when the process was suspended and resumed
  // around a playback session (the wakelock sleep investigation).
  // The binding holds the observer for the app's lifetime.
  LifecycleLogger(container.read(diagLogProvider)).attach();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TmhbApp(),
    ),
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
