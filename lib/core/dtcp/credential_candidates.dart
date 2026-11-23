/// Selecting importable credential files among scanned Downloads
/// files (plan 127).
///
/// The Downloads scan hands over every file it found; this is the
/// pure half that decides which of them the import screen may
/// offer: the name must follow the `credentials*.env` shape, the
/// contents must parse as a credentials.env file, and the parsed
/// pair must pass pair validation — the caller passes the
/// credential store's own check in, so the listing and the save
/// can never disagree about what a genuine pair is. A file that
/// fails any step is simply not offered; its contents are never
/// shown, and the failure reasons stay out of the UI.
///
/// The name rule is case-insensitive: the folder is written by
/// other tools on other systems, and a file the user means as
/// their credentials file should not be missed over casing.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'credentials_env.dart';

/// A scanned file whose name matched the credentials shape:
/// its base name and its whole contents.
typedef ScannedCredentialFile = ({String name, Uint8List bytes});

/// A Downloads file that can be imported: it matched the name
/// rule, parsed, and passed pair validation. [env] holds the
/// parsed pair in memory only, for the import the user goes on
/// to confirm; nothing here is ever displayed beyond [name] and
/// [sizeBytes].
class CredentialFileCandidate {
  const CredentialFileCandidate({
    required this.name,
    required this.sizeBytes,
    required this.env,
  });

  /// The file's base name (metadata only).
  final String name;

  /// The file's size in bytes (metadata only).
  final int sizeBytes;

  /// The parsed, validated pair. Never shown.
  final CredentialsEnv env;
}

/// Whether [name] follows the `credentials*.env` shape
/// (case-insensitive): `credentials.env`, `credentials2.env` and
/// `credentials-backup.env` match; `mycredentials.env`,
/// `credentials.txt` and `credentials.env.bak` do not.
bool isCredentialEnvFileName(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('credentials') && lower.endsWith('.env');
}

/// The importable candidates among [files], in name order.
/// [validate] is the credential store's pair check. Files that
/// fail to decode, parse or validate are skipped silently.
List<CredentialFileCandidate> selectCredentialCandidates(
  Iterable<ScannedCredentialFile> files, {
  required bool Function(CredentialsEnv env) validate,
}) {
  final candidates = <CredentialFileCandidate>[];
  for (final file in files) {
    if (!isCredentialEnvFileName(file.name)) continue;
    final CredentialsEnv env;
    try {
      env = parseCredentialsEnv(utf8.decode(file.bytes));
    } catch (_) {
      continue; // Not a readable credentials.env: not a candidate.
    }
    if (!validate(env)) continue;
    candidates.add(
      CredentialFileCandidate(
        name: file.name,
        sizeBytes: file.bytes.length,
        env: env,
      ),
    );
  }
  candidates.sort((a, b) => a.name.compareTo(b.name));
  return candidates;
}
