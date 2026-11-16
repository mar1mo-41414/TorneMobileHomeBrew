/// torne mobile HomeBrew edition — app entry point.
///
/// Before the first frame, the local stores are backed by JSON files
/// in the application documents directory so registrations and caches
/// survive restarts (app/bootstrap.dart). The UI is the v1 screen set
/// of plan 5.6, built on the phase 1 core through the composition
/// root (app/providers.dart) and app state (app/state.dart).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
// Flutter 3.50 deprecates package:flutter/material.dart in favour of
// package:material_ui/material_ui.dart (the scaffold's own import).
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app/bootstrap.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final documentsDirectory = await getApplicationDocumentsDirectory();
  runApp(
    UncontrolledProviderScope(
      container: fileStoreContainer(documentsDirectory),
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const AppShell(),
    );
  }
}
