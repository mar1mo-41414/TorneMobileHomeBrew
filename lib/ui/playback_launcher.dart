/// Shared playback-start flow (plan 39, extracted from the title
/// detail view where it was built for recordings in plan 28/33):
/// run the engine start, push the player screen on success, and
/// turn each failure category into its dialog — the unsupported
/// notice, the credential-import guidance, or the classified
/// error dialog that names the failing stage. Recorded playback
/// and live viewing share this; only the start call, the player
/// screen and the wording differ.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../core/core.dart';
import 'dtcp_credential_screen.dart';
import 'error_messages.dart';
import 'widgets.dart';

/// Starts a session via [start] and shows the player built by
/// [buildPlayer]. A start that finishes after the caller has
/// left is stopped again immediately. [unsupportedSubject] names
/// what cannot play in the unsupported notice (録画の再生 /
/// TV視聴); [startFailureMessage] is the fallback snack for
/// unclassified failures.
Future<void> startPlaybackAndShowPlayer({
  required BuildContext context,
  required WidgetRef ref,
  required Future<PlaybackSession> Function() start,
  required Widget Function(PlaybackSession session) buildPlayer,
  required String unsupportedSubject,
  String startFailureMessage = '再生を開始できませんでした',
}) async {
  try {
    final session = await start();
    if (!context.mounted) {
      await session.stop();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => buildPlayer(session)),
    );
  } on NasneError catch (e) {
    if (!context.mounted) return;
    if (e.category == NasneErrorCategory.unsupported) {
      await showPlaybackUnsupportedDialog(
        context,
        subject: unsupportedSubject,
      );
    } else if (e.category == NasneErrorCategory.validation) {
      await showCredentialGuidanceDialog(context, userMessageForError(e));
    } else {
      // Name the failing stage instead of collapsing everything
      // into one opaque snack (plan 28): the dialog carries the
      // classification (category / source / code / detail), and
      // the failure is recorded under the ui category when debug
      // mode is on. No credential or key material is included.
      ref.read(diagLogProvider)(DiagCategory.ui, 'playback start failed: $e');
      await showPlaybackErrorDialog(context, e);
    }
  } catch (e) {
    if (!context.mounted) return;
    ref.read(diagLogProvider)(
      DiagCategory.ui,
      'playback start failed (unclassified): $e',
    );
    showSnack(context, startFailureMessage);
  }
}

/// The classified playback error dialog (plan 28).
Future<void> showPlaybackErrorDialog(BuildContext context, NasneError e) {
  final detail = StringBuffer(userMessageForError(e));
  detail.write('\n\n分類: ${e.category.name} / 発生元: ${e.source}');
  if (e.code != null) detail.write(' / コード: ${e.code}');
  if (e.detail != null) detail.write('\n詳細: ${e.detail}');
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('再生を開始できませんでした'),
      content: Text(detail.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

/// Guidance shown when the credential pair has not been imported.
///
/// Plan 86.2 (plan 85 item 2): the dialog leads straight to the
/// import screen. Before this its only action was "close", and
/// the viewer had to go and find the credential entry in the
/// settings tab themselves — the step where the playback path
/// lost people who did not already know the app.
Future<void> showCredentialGuidanceDialog(
  BuildContext context,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('資格情報が必要です'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        FilledButton(
          onPressed: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => const DtcpCredentialScreen(),
              ),
            );
          },
          child: const Text('インポートする'),
        ),
      ],
    ),
  );
}

/// The notice shown when the configured engine cannot play.
Future<void> showPlaybackUnsupportedDialog(
  BuildContext context, {
  required String subject,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('再生は未実装です'),
      content: Text(
        '$subjectには DTCP-IP の資格情報 (DTLA 署名の証明書と機器秘密鍵のペア) '
        'が必要です。資格情報ペアが得られていないため、再生は未実装です。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}
