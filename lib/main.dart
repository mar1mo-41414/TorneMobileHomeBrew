/// torne mobile HomeBrew edition — phase 1 composition-root shell.
///
/// The full UI arrives in phase 2 (iOS). This shell exists so the app
/// target builds around the real provider graph from day one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
// Flutter 3.50 deprecates package:flutter/material.dart in favour of
// package:material_ui/material_ui.dart (the scaffold's own import).
import 'package:material_ui/material_ui.dart';

import 'app/providers.dart';

void main() {
  runApp(const ProviderScope(child: TmhbApp()));
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
              const Text('フェーズ1: コア実装済み。UI はフェーズ2で実装します。'),
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
