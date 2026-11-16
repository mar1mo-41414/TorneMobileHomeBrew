/// torne mobile HomeBrew edition — app entry point.
///
/// Phase 2 wiring: before the first frame, the local stores are
/// backed by JSON files in the application documents directory so
/// registrations and caches survive restarts (app/bootstrap.dart).
/// The screens are still the phase 1 shell; the v1 UI is built on
/// top of this provider graph.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Flutter 3.50 deprecates package:flutter/material.dart in favour of
// package:material_ui/material_ui.dart (the scaffold's own import).
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app/bootstrap.dart';
import 'app/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      title: 'torne mobile HomeBrew',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackEngineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('torne mobile HomeBrew')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'torne mobile HomeBrew エディション',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('フェーズ2: コア実装済み。これは実機確認用シェルです。'),
              const SizedBox(height: 12),
              Text(
                playback.isSupported
                    ? '再生: 対応'
                    : '再生: 未実装 (DTCP-IP の資格情報が必要です)',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
