/// Shared UI building blocks: async section handling, cards, and
/// simple placeholder views. Screens compose these so loading and
/// error presentation stay uniform.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/core.dart';
import 'error_messages.dart';
import 'tv_focus.dart';

/// Full-area loading indicator.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Error display with an optional retry action.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('再試行')),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled card used to group one home-screen section.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] as data / loading / error, uniformly.
Widget asyncSection<T>(
  AsyncValue<T> value,
  Widget Function(T data) builder, {
  VoidCallback? onRetry,
}) {
  return value.when(
    data: builder,
    loading: () => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()),
    ),
    error: (e, _) => Padding(
      padding: const EdgeInsets.all(12),
      child: ErrorView(message: userMessageForError(e), onRetry: onRetry),
    ),
  );
}

/// A label/value row for detail views.
class FieldRow extends StatelessWidget {
  const FieldRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// Resolves the display name of the channel a schedule / title refers
/// to, falling back to the raw service id when the channel list is
/// unavailable.
String channelDisplayName(List<Channel>? channels, ScheduleChannel? channel) {
  if (channel == null) return '不明';
  if (channels != null) {
    for (final c in channels) {
      if (c.serviceId == channel.serviceId &&
          c.broadcastingType == channel.broadcastingType) {
        return c.serviceName;
      }
    }
  }
  return 'サービス ${channel.serviceIdHex}';
}

/// Shows a transient message at the bottom of [context]'s scaffold.
void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Confirmation dialog; resolves to true only on explicit confirm.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '削除',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        // TV: this confirmation is destructive by default (the
        // default label is 削除), so focus starts on cancel: the
        // dialog must be operable by remote, but one stray OK
        // must not carry the action out (plan 134).
        TextButton(
          autofocus: isTvVariant(context),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Cause-based checks for when discovery finds no nasne (plan 86.4).
/// Written for users who do not know the network vocabulary: each
/// item names a concrete thing to look at, in roughly the order it
/// most often turns out to be the cause.
const List<String> discoveryChecklistItems = [
  'nasne の電源が入っていて、起動が終わっていること',
  'この端末が、nasne と同じ Wi-Fi (同じネットワーク) につながっていること',
  'ルーターの「端末同士の通信を止める」設定 (プライバシーセパレータ、AP アイソレーションなど) がオフになっていること',
  'このアプリにローカルネットワークへのアクセスが許可されていること (iOS では「設定」アプリから確認できます)',
];

/// The discovery-failure checklist block (plan 86.4), shared by the
/// settings screen's "not found" and search-error states.
class DiscoveryChecklist extends StatelessWidget {
  const DiscoveryChecklist({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '見つからないときは、次の点を確認してください。',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        for (final item in discoveryChecklistItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shared "no nasne registered yet" guidance (plan 86.4): the same
/// view on every tab, with a button that jumps to the settings tab
/// where registration happens.
class NoDeviceView extends StatelessWidget {
  const NoDeviceView({super.key, required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tv_off_outlined, size: 48),
            const SizedBox(height: 16),
            const Text('nasne が登録されていません'),
            const SizedBox(height: 8),
            const Text(
              '使うには、まず nasne を登録してください。設定画面で探して登録できます。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRegister,
              icon: const Icon(Icons.settings),
              label: const Text('設定で登録する'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dismisses the software keyboard when a tap lands outside
/// the focused text field (plan 54). The app wraps its whole
/// UI in this (see main.dart): the field screens had no
/// unfocus path at all — no tap-outside handling, no done
/// action — so on iOS, whose keyboard offers no dismiss key
/// for these input types, opening a field (the manual
/// registration field was the reported case) trapped the
/// keyboard on screen with no way to close it.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: child,
    );
  }
}
