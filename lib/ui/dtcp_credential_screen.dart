/// DTCP-IP credential import screen (Phase 5, plan 26.4).
///
/// The user imports their own device pair (DTLA certificate 88
/// bytes + private key 20 bytes) obtained from their own equipment.
/// The pair is validated, then stored only in the OS vault. The
/// bytes are never shown after entry, never logged, and the text
/// fields are cleared as soon as the import completes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
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

  Future<Uint8List?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.bytes;
  }

  Future<void> _import() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final certificate = _certFileBytes ?? _decodePasted(_certText.text);
      final privateKey = _keyFileBytes ?? _decodePasted(_keyText.text);
      await ref
          .read(credentialStoreProvider)
          .save(certificate: certificate, privateKey: privateKey);
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
    } catch (e) {
      setState(() => _error = '$e');
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
            '録画の再生には、対応機器の DTCP-IP 資格情報 (DTLA 証明書 88 バイトと'
            '秘密鍵 20 バイト) が必要です。ご自身の機器から取得したペアをここで'
            'インポートしてください。資格情報は端末の金庫 (Keychain / Keystore) '
            'にのみ保存され、外部に送信されることはありません。',
          ),
          const SizedBox(height: 16),
          summary.when(
            data: (value) => value == null
                ? const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('未インポート'),
                  )
                : ListTile(
                    leading: const Icon(Icons.verified_user),
                    title: const Text('インポート済み'),
                    subtitle: Text(
                      'デバイス ID: ${value.deviceIdHex}\n'
                      '証明書 SHA-1: ${value.certificateSha1Hex}',
                    ),
                  ),
            loading: () => const ListTile(title: Text('確認中…')),
            error: (e, _) => ListTile(title: Text('読み込みエラー: $e')),
          ),
          const Divider(),
          _pairFields(
            label: '証明書 (88 バイト)',
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
            label: '秘密鍵 (20 バイト)',
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
            onPressed: _busy ? null : _import,
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
            title: Text('ファイルから読み込み済み (${fileBytes.length} バイト)'),
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
              hintText: 'hex または base64 を貼り付け',
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
