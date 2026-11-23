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
/// Since plan 127, on Android the file can also be found instead
/// of picked: the Downloads folder is scanned for
/// `credentials*.env`-shaped files, and only those whose parsed
/// pair passes the credential store's own validation are listed
/// (by name only). Importing a listed file still takes a
/// per-file confirmation and the same validation + save as every
/// other path. Android TV has no usable file picker, which is
/// what this path exists for.
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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../app/providers.dart';
import '../core/core.dart';
import 'format.dart';
import 'tv_focus.dart';

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
        () => _error =
            'ファイルを読み取れませんでした。'
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
          () => _error =
              'ファイルから証明書と秘密鍵を取り出せませんでした。'
              '資格情報ファイル (credentials.env) かどうか確認してください。',
        );
      }
      return;
    }
    await _import(certificate: env.certificate, privateKey: env.privateKey);
  }

  /// Finds importable credential files in the Downloads folder
  /// (plan 127; the button is shown only where the scanner
  /// provider is non-null, i.e. Android). Only files whose parsed
  /// pair passes the credential store's own validation are
  /// listed, by name only; importing one takes the per-file
  /// confirmation and then the exact same validation + vault
  /// save as the picked-file import above. A scan that cannot
  /// read the folder is reported in plain words, with the
  /// platform failure itself recorded in the diagnostics log.
  Future<void> _scanDownloads() async {
    final scanner = ref.read(credentialDownloadsScannerProvider);
    if (scanner == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await scanner.scan();
      if (!mounted) return;
      final store = ref.read(credentialStoreProvider);
      final candidates = selectCredentialCandidates(
        files.map((f) => (name: f.name, bytes: f.bytes)),
        validate: (env) => store.validates(
          certificate: env.certificate,
          privateKey: env.privateKey,
        ),
      );
      // Metadata only (names and sizes, never contents): the
      // record that tells "the scan read the file but it did
      // not pass" apart from "the scan never saw the file",
      // for when a placed file does not show up (plan 132).
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'credential downloads scan: read '
        '[${files.map((f) => '${f.name} (${f.bytes.length} bytes)').join(', ')}], '
        'candidates [${candidates.map((c) => c.name).join(', ')}]',
      );
      if (candidates.isEmpty) {
        setState(
          () => _error =
              'ダウンロードフォルダに、取り込める資格情報ファイルが'
              '見つかりませんでした。ファイル名が credentials で始まる'
              ' .env ファイルになっているか確認してください。',
        );
        return;
      }
      final chosen = await _chooseCandidate(candidates);
      if (chosen == null || !mounted) return;
      final confirmed = await _confirmCandidate(chosen);
      if (confirmed != true || !mounted) return;
      await _import(
        certificate: chosen.env.certificate,
        privateKey: chosen.env.privateKey,
      );
    } on PlatformException catch (e) {
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'credential downloads scan failed: $e',
      );
      if (mounted) {
        setState(
          () => _error = e.code == 'permission_denied'
              ? 'ダウンロードフォルダを読み取る許可がないため、探せませんでした。'
                    '端末の設定でこのアプリにストレージの許可を与えてから、'
                    'もう一度お試しください。'
              : 'ダウンロードフォルダを探せませんでした。もう一度お試しください。',
        );
      }
    } catch (e) {
      ref.read(diagLogProvider)(
        DiagCategory.ui,
        'credential downloads scan failed: $e',
      );
      if (mounted) {
        setState(() => _error = 'ダウンロードフォルダを探せませんでした。もう一度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Lists the importable files found in Downloads, by name and
  /// size only — never their contents — and returns the one the
  /// user picked, or null when the list was dismissed.
  Future<CredentialFileCandidate?> _chooseCandidate(
    List<CredentialFileCandidate> candidates,
  ) {
    return showDialog<CredentialFileCandidate>(
      context: context,
      builder: (context) {
        // TV: the first candidate takes focus as the dialog
        // opens. Without an autofocus element the D-pad focus
        // stays on the screen behind the dialog, and neither
        // the list nor cancel can be reached at all (plan 134).
        final tv = isTvVariant(context);
        return AlertDialog(
          title: const Text('資格情報ファイルが見つかりました'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final candidate = candidates[index];
                return ListTile(
                  autofocus: tv && index == 0,
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(candidate.name),
                  subtitle: Text(formatBytes(candidate.sizeBytes)),
                  onTap: () => Navigator.pop(context, candidate),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  /// The per-file confirmation before a found file is imported:
  /// nothing from Downloads reaches the vault without it.
  Future<bool?> _confirmCandidate(CredentialFileCandidate candidate) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('資格情報を取り込む'),
        content: Text('「${candidate.name}」から証明書と秘密鍵を取り込みます。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          // TV: focus the confirm action as the dialog opens
          // (plan 134).
          TextButton(
            autofocus: isTvVariant(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取り込む'),
          ),
        ],
      ),
    );
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
          () => _error =
              '貼り付けた内容を読み取れませんでした。'
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
          () => _error =
              '証明書と秘密鍵のペアとして確認できませんでした。'
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
          // TV: deletion is destructive, so focus starts on
          // cancel, not on the delete action (plan 134).
          TextButton(
            autofocus: isTvVariant(context),
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
    final downloadsScanner = ref.watch(credentialDownloadsScannerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('DTCP-IP 資格情報')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          // TV: the intro text holds focus (TvFocusAnchor) so
          // D-pad traversal can scroll back to the top of the
          // list (plan 123). The last item is a button and
          // already takes focus.
          const TvFocusAnchor(
            child: Text(
              '録画を再生するには、お持ちの対応機器から取り出した'
              '「証明書」と「秘密鍵」のペアが必要です。',
            ),
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
          Text('ファイルから読み込む', style: Theme.of(context).textTheme.titleSmall),
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
          if (downloadsScanner != null) ...[
            const SizedBox(height: 6),
            const Text(
              'テレビなどファイルを選ぶ画面が使えない環境では、'
              'ダウンロードフォルダに資格情報ファイルを置いておくと、'
              'そこから探して取り込むこともできます。',
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _busy ? null : _scanDownloads,
              icon: const Icon(Icons.search),
              label: const Text('Downloads から探す'),
            ),
          ],
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
          AppTextField(
            controller: controller,
            tvEditTitle: label,
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
