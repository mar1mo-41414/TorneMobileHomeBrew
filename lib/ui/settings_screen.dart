/// Settings screen (plan 5.6 item 4): registration management only —
/// SSDP discovery, manual address registration (both verified by
/// PINVerify through the RegistrationService), re-verification, and
/// unregistration. Device settings themselves are out of the v1
/// scope (plan 1.2).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../app/state.dart';
import '../core/core.dart';
import 'error_messages.dart';
import 'format.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _searching = false;
  List<NasneDevice>? _found;
  String? _searchError;
  bool _registering = false;
  final _manualHost = TextEditingController();

  @override
  void dispose() {
    _manualHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registrations = ref.watch(registrationsProvider);
    final selected = ref.watch(selectedRegistrationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          _sectionTitle(context, '登録済み nasne'),
          registrations.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(userMessageForError(e)),
            ),
            data: (list) => Column(
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('登録済みの nasne はありません。下の「探す」か手動登録で追加してください。'),
                  ),
                for (final reg in list)
                  ListTile(
                    leading: Icon(
                      selected?.host == reg.host
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(reg.friendlyName),
                    subtitle: Text('${reg.host}\nMAC ${maskMac(reg.macAddr)}'),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) =>
                          _onRegistrationAction(action, reg),
                      itemBuilder: (context) => [
                        if (selected?.host != reg.host)
                          const PopupMenuItem(
                            value: 'select',
                            child: Text('この nasne を使う'),
                          ),
                        const PopupMenuItem(
                          value: 'verify',
                          child: Text('登録を検証'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('登録を解除'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          _sectionTitle(context, 'nasne を探す'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: _searching ? null : _discover,
                  icon: const Icon(Icons.search),
                  label: Text(_searching ? '検索中…' : 'LAN 内の nasne を探す'),
                ),
                if (_searchError != null) ...[
                  const SizedBox(height: 8),
                  Text(_searchError!),
                ],
                if (_found != null) ...[
                  const SizedBox(height: 8),
                  if (_found!.isEmpty)
                    const Text('見つかりませんでした。手動登録をお試しください。')
                  else
                    for (final device in _found!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.tv_outlined),
                        title: Text(device.friendlyName),
                        subtitle: Text(device.host),
                        trailing: FilledButton.tonal(
                          onPressed: _registering
                              ? null
                              : () => _registerDevice(device),
                          child: const Text('登録'),
                        ),
                      ),
                ],
              ],
            ),
          ),
          const Divider(),
          _sectionTitle(context, '手動登録'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _manualHost,
                  decoration: const InputDecoration(
                    labelText: 'IP アドレス / ホスト名',
                    hintText: '192.168.11.129',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _registering ? null : _registerManual,
                  icon: const Icon(Icons.add),
                  label: const Text('登録'),
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '発見にはローカルネットワークへのアクセス許可が必要です (iOS では許可ダイアログが'
              '表示される場合があります)。発見できない環境では手動登録を使ってください。\n\n'
              'torne mobile HB バージョン 1.0.0',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Future<void> _discover() async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final found = await ref.read(discoveryServiceProvider).discover();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = found;
      });
    } on NasneError catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = userMessageForError(e);
      });
    }
  }

  Future<void> _registerDevice(NasneDevice device) async {
    setState(() => _registering = true);
    try {
      final registration = await ref
          .read(registrationServiceProvider)
          .register(device);
      await ref.read(registrationsProvider.notifier).add(registration);
      ref.read(selectedHostProvider.notifier).select(registration.host);
      if (!mounted) return;
      showSnack(context, '登録しました: ${registration.host}');
    } on NasneError catch (e) {
      if (!mounted) return;
      showSnack(context, userMessageForError(e));
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _registerManual() async {
    final host = _manualHost.text.trim();
    if (host.isEmpty) {
      showSnack(context, 'アドレスを入力してください');
      return;
    }
    setState(() => _registering = true);
    NasneDevice device;
    try {
      device = await ref
          .read(discoveryServiceProvider)
          .describe(Uri(scheme: 'http', host: host, port: 58888, path: '/'));
    } catch (_) {
      // The description may be unreachable while the device itself is
      // fine; registration re-verifies against the device directly.
      device = NasneDevice.direct(host);
    }
    if (!mounted) return;
    await _registerDevice(device);
  }

  Future<void> _onRegistrationAction(String action, RegisteredNasne reg) async {
    switch (action) {
      case 'select':
        ref.read(selectedHostProvider.notifier).select(reg.host);
      case 'verify':
        try {
          final ok = await ref.read(registrationServiceProvider).verify(reg);
          if (!mounted) return;
          showSnack(
            context,
            ok ? '検証 OK: ${reg.host}' : '検証に失敗しました: ${reg.host}',
          );
        } on NasneError catch (e) {
          if (!mounted) return;
          showSnack(context, userMessageForError(e));
        }
      case 'remove':
        final ok = await confirmDialog(
          context,
          title: '登録を解除',
          message: '${reg.friendlyName} (${reg.host}) の登録を解除しますか？',
          confirmLabel: '解除',
        );
        if (!ok) return;
        await ref.read(registrationsProvider.notifier).remove(reg.host);
        if (ref.read(selectedHostProvider) == reg.host) {
          ref.read(selectedHostProvider.notifier).select(null);
        }
        if (!mounted) return;
        showSnack(context, '登録を解除しました');
    }
  }
}
