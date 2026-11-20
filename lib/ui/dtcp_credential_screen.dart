/// DTCP-IP credential import screen (Phase 5, plan 26.4).
///
/// The user imports their own device pair (DTLA certificate 88
/// bytes + private key 20 bytes) obtained from their own equipment.
/// The pair is validated, then stored only in the OS vault. The
/// bytes are never shown after entry, never logged, and the text
/// fields are cleared as soon as the import completes.
///
/// Since plan 67 the pair can also be imported from a pydtcpip-style
/// credentials.env file; that path feeds the same validation + save
/// as the manual entry kept below it.
///
/// Since plan 84 a failed file pick is logged and shown as an
/// error instead of escaping silently (the plan 69.5 leftover).
///
/// Plan 86.2 (plan 85 item 2): the surface speaks plainly. The
/// internal facts a viewer never acts on — byte counts, the
/// certificate's SHA-1, the device ID in hex, the env file's
/// variable names — are gone from the text; what remains is
/// what to prepare, in which order, and what to do when
/// something fails. Failures are shown as a plain sentence plus
/// the next action; the raw error goes to the diagnostics log
/// only. The validation itself is unchanged.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../core/core.dart';

class DtcpCredentialScreen extends ConsumerStatefulWidget {
  const DtcpCredentialScreen({super.key});

  @override
  ConsumerState<DtcpCredentialScreen> createState() =>
      _DtcpCredentialScreenState();
}

class _DtcpCredentialScreenState extends ConsumerState<DtcpCredentialScreen> {
  final _certText = TextEditingController();
  final _keyText = TextEditingController();
  Uint8List? _certFileBytes;
  Uint8List? _keyFileBytes;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _certText.dispose();
    _keyText.dispose();
    super.dispose();
  }

  /// Decodes pasted input: hex (whitespace tolerant) or base64.
  static Uint8List _decodePasted(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) {
      throw NasneError.validation('dtcp:import', '入力が空です');
    }
    if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(compact) && compact.length.isEven) {
      return hexToBytes(compact.toLowerCase());
    }
    try {
      return base64Decode(compact);
    } on FormatException {
      throw NasneError.validation(
        'dtcp:import',
        'hex または base64 として解釈できませんでした',
      );
    }
  }

  /// Picks a file through [FileBytesPicker]. A cancelled pick
  /// returns null and stays silent (a normal outcome); a failed
  /// pick also returns null, but first leaves a diagnostics
  /// record and a visible error — the plan 69.5 leftover, where
  /// a picker exception escaped unhandled and the button looked
  /// dead. The failure presentation follows plan 71: never
  /// swallow, log the detail, tell the user. The shown text is
  /// plain (plan 86.2); the exception itself stays in the log.
  Future<Uint8List?> _pickFile() async {
    try {
      return await ref.read(fileBytesPickerProvider).pick();
    } catch (e) {
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'credential file pick failed: $e',
      );
      if (mounted) {
        setState(() => _error = 'ファイル選択に失敗しました。もう一度お試しください。');
      }
      return null;
    }
  }

  /// Imports from a credentials.env file (plan 67): picking the
  /// file is all the user does — the parsed pair goes through
  /// the exact same validation + vault save as the manual entry
  /// below. A file that does not yield a pair is reported in
  /// plain words (plan 86.2), with the parse failure itself
  /// recorded in the diagnostics log.
  Future<void> _importFromEnvFile() async {
    final bytes = await _pickFile();
    if (bytes == null) return;
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      setState(
        () => _error = 'ファイルを読み取れませんでした。'
            '資格情報ファイル (credentials.env) かどうか確認してください。',
      );
      return;
    }
    final CredentialsEnv env;
    try {
      env = parseCredentialsEnv(text);
    } catch (e) {
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'credentials.env parse failed: $e',
      );
      if (mounted) {
        setState(
          () => _error = 'ファイルから証明書と秘密鍵を取り出せませんでした。'
              '資格情報ファイル (credentials.env) かどうか確認してください。',
        );
      }
      return;
    }
    await _import(certificate: env.certificate, privateKey: env.privateKey);
  }

  Future<void> _import({Uint8List? certificate, Uint8List? privateKey}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final Uint8List certificateBytes;
      final Uint8List privateKeyBytes;
      try {
        certificateBytes =
            certificate ?? _certFileBytes ?? _decodePasted(_certText.text);
        privateKeyBytes =
            privateKey ?? _keyFileBytes ?? _decodePasted(_keyText.text);
      } on NasneError catch (e) {
        ref.read(diagLogProvider)(
          DiagCategory.ui,
          'credential entry decode failed: $e',
        );
        setState(
          () => _error = '貼り付けた内容を読み取れませんでした。'
              '証明書・秘密鍵の内容がそのまま入っているか確認してください。',
        );
        return;
      }
      try {
        await ref
            .read(credentialStoreProvider)
            .save(certificate: certificateBytes, privateKey: privateKeyBytes);
      } catch (e) {
        ref.read(diagLogProvider)(
          DiagCategory.ui,
          'credential pair validation failed: $e',
        );
        setState(
          () => _error = '証明書と秘密鍵のペアとして確認できませんでした。'
              '同じ機器から取り出したペアになっているか、'
              '内容が欠けていないか確認してください。',
        );
        return;
      }
      // Clear the entry surfaces immediately; the pair now lives
      // only in the vault.
      _certText.clear();
      _keyText.clear();
      _certFileBytes = null;
      _keyFileBytes = null;
      ref.invalidate(credentialSummaryProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('資格情報を保存しました')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('資格情報を削除'),
        content: const Text('保存済みの証明書と秘密鍵を端末の金庫から削除します。削除すると録画の再生はできなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(credentialStoreProvider).delete();
    ref.invalidate(credentialSummaryProvider);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('資格情報を削除しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(credentialSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('DTCP-IP 資格情報')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '録画を再生するには、お持ちの対応機器から取り出した'
            '「証明書」と「秘密鍵」のペアが必要です。',
          ),
          const SizedBox(height: 16),
          Text('用意のしかた', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          const Text(
            '1. 対応機器から証明書と秘密鍵を取り出します'
            ' (このアプリ自体に取り出す機能はありません)。\n'
            '2. ファイル (credentials.env) で用意できた場合は、'
            '下の「ファイルから読み込む」から選ぶだけで完了します。\n'
            '3. テキストで用意した場合は、その下の欄に貼り付けます。\n\n'
            '取り込んだ内容はこの端末の中にだけ保存され、'
            '外部に送られることはありません。',
          ),
          const SizedBox(height: 16),
          summary.when(
            data: (value) => value == null
                ? const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('未インポート'),
                  )
                : const ListTile(
                    leading: Icon(Icons.verified_user),
                    title: Text('インポート済み'),
                  ),
            loading: () => const ListTile(title: Text('確認中…')),
            error: (e, _) => const ListTile(title: Text('状態を確認できませんでした')),
          ),
          const Divider(),
          Text(
            'ファイルから読み込む',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            '資格情報ファイル (credentials.env) を選ぶと、'
            'そのまま確認して保存します。',
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importFromEnvFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('ファイルを選択'),
          ),
          const SizedBox(height: 16),
          Text('テキストで入力する', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          _pairFields(
            label: '証明書',
            controller: _certText,
            fileBytes: _certFileBytes,
            onPick: () async {
              final bytes = await _pickFile();
              if (bytes != null) setState(() => _certFileBytes = bytes);
            },
            onClearFile: () => setState(() => _certFileBytes = null),
          ),
          const SizedBox(height: 16),
          _pairFields(
            label: '秘密鍵',
            controller: _keyText,
            fileBytes: _keyFileBytes,
            onPick: () async {
              final bytes = await _pickFile();
              if (bytes != null) setState(() => _keyFileBytes = bytes);
            },
            onClearFile: () => setState(() => _keyFileBytes = null),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : () => _import(),
            icon: const Icon(Icons.download_done),
            label: const Text('検証して保存'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('保存済みの資格情報を削除'),
          ),
        ],
      ),
    );
  }

  Widget _pairFields({
    required String label,
    required TextEditingController controller,
    required Uint8List? fileBytes,
    required Future<void> Function() onPick,
    required VoidCallback onClearFile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (fileBytes != null)
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: const Text('ファイルから読み込み済み'),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClearFile,
            ),
          )
        else ...[
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '内容をそのまま貼り付け',
            ),
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open),
            label: const Text('ファイルから読み込む'),
          ),
        ],
      ],
    );
  }
}
