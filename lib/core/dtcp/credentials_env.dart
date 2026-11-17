/// Parser for pydtcpip-style `credentials.env` files (plan 67).
///
/// The rescue tooling (SonyNasne-DTCP `tools/dtcpip-rescue`) keeps
/// the user's DTCP-IP pair in a dotenv-shaped file:
///
/// ```text
/// PYDTCPIP_CERTIFICATE=<hex>
/// PYDTCPIP_PRIVATE_KEY=<hex>
/// ```
///
/// This parser only understands that *format*: it extracts the two
/// hex values and decodes them to bytes. Whether the pair is a
/// genuine DTLA pair is decided later by the exact same validation
/// path as the paste-in import ([DeviceCredentials] via the
/// credential store). Error messages name variables and format
/// problems only — they never echo the values themselves.
library;

import 'dart:typed_data';

import '../errors.dart';
import 'dtcp_crypto.dart';

/// A credential pair decoded from a credentials.env file. The bytes
/// are unvalidated at this point; validation happens in
/// [DeviceCredentials] when the pair is saved.
class CredentialsEnv {
  const CredentialsEnv({required this.certificate, required this.privateKey});

  final Uint8List certificate;
  final Uint8List privateKey;
}

/// Parses [text] (the whole file contents) as a credentials.env
/// file.
///
/// Tolerated, matching how such files are written in practice:
/// comment lines (`#` / `;`), blank lines, CRLF line endings,
/// whitespace around `=` and inside the hex value, single- or
/// double-quoted values, an optional `export ` prefix, trailing
/// inline comments on unquoted values, and unrelated variables
/// (ignored). Both variables are required.
CredentialsEnv parseCredentialsEnv(String text) {
  String? certificateHex;
  String? privateKeyHex;
  for (final rawLine in text.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) {
      continue;
    }
    if (line.startsWith('export ')) {
      line = line.substring('export '.length).trimLeft();
    }
    final eq = line.indexOf('=');
    if (eq < 0) {
      throw NasneError.validation(
        'dtcp:import',
        'credentials.env has a line that is not a KEY=value assignment',
      );
    }
    final name = line.substring(0, eq).trim().toUpperCase();
    final value = _cleanValue(line.substring(eq + 1));
    switch (name) {
      case 'PYDTCPIP_CERTIFICATE':
        certificateHex = value;
      case 'PYDTCPIP_PRIVATE_KEY':
        privateKeyHex = value;
      default:
        break; // Unrelated variables are ignored.
    }
  }
  return CredentialsEnv(
    certificate: _decodeHex(certificateHex, 'PYDTCPIP_CERTIFICATE'),
    privateKey: _decodeHex(privateKeyHex, 'PYDTCPIP_PRIVATE_KEY'),
  );
}

/// Strips quoting and trailing comments from a raw value and removes
/// all whitespace (hex values may be pasted with spaces or wrapped).
String _cleanValue(String raw) {
  var value = raw.trim();
  if (value.startsWith('"') || value.startsWith("'")) {
    // Quoted value: take everything up to the matching closing
    // quote; anything after it (e.g. an inline comment) is ignored.
    final end = value.indexOf(value[0], 1);
    if (end > 0) {
      return value
          .substring(1, end)
          .trim()
          .replaceAll(RegExp(r'\s+'), '');
    }
  }
  final hash = value.indexOf('#');
  if (hash >= 0) value = value.substring(0, hash).trim();
  return value.replaceAll(RegExp(r'\s+'), '');
}

Uint8List _decodeHex(String? value, String variable) {
  if (value == null ||
      value.isEmpty ||
      value.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw NasneError.validation(
      'dtcp:import',
      '$variable is missing or is not an even-length hex string',
    );
  }
  return hexToBytes(value.toLowerCase());
}
