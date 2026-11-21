/// The hidden-genre selection (plan 95, Discord request
/// 2026-11-21): the viewer marks the programme-guide genres
/// they do not watch, and events of those genres paint blank
/// in the guide grid. Reached from the settings screen's
/// 番組表 section; the choice persists through
/// [HiddenEpgGenresNotifier].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import 'epg_genre.dart';

class EpgHiddenGenresScreen extends ConsumerWidget {
  const EpgHiddenGenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenEpgGenresProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('見ないジャンル')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('選んだジャンルの番組は、番組表で空白表示になります。'),
          ),
          for (final value in epgGenreLevel1Values)
            CheckboxListTile(
              secondary: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: epgGenreColor(value),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              title: Text(epgGenreLabel(value)!),
              value: hidden.contains(value),
              onChanged: (checked) => ref
                  .read(hiddenEpgGenresProvider.notifier)
                  .setHidden(value, checked ?? false),
            ),
        ],
      ),
    );
  }
}
