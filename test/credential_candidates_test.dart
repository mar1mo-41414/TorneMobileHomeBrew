/// Tests for the Downloads candidate selection (plan 127).
///
/// All values are the published known-answer dummies from
/// dtcp_kat.dart (test authority pair) — never real credentials.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

import 'dtcp_kat.dart';

bool _validateWithTestAuthority(CredentialsEnv env) {
  try {
    DeviceCredentials(
      certificate: env.certificate,
      privateKey: env.privateKey,
      authorityKeys: [hexToBytes(katAuthPub)],
    );
    return true;
  } on NasneError {
    return false;
  }
}

Uint8List _envBytes(String certificate, String privateKey) =>
    Uint8List.fromList(
      utf8.encode(
        'PYDTCPIP_CERTIFICATE=$certificate\n'
        'PYDTCPIP_PRIVATE_KEY=$privateKey\n',
      ),
    );

ScannedCredentialFile _file(String name, Uint8List bytes) =>
    (name: name, bytes: bytes);

void main() {
  group('isCredentialEnvFileName', () {
    test('matches the credentials*.env shape', () {
      expect(isCredentialEnvFileName('credentials.env'), isTrue);
      expect(isCredentialEnvFileName('credentials2.env'), isTrue);
      expect(isCredentialEnvFileName('credentials-backup.env'), isTrue);
      expect(isCredentialEnvFileName('credentials.env.env'), isTrue);
    });

    test('matches names with a dotted middle (device-suffixed)', () {
      // The rule is a prefix plus a suffix, not a single fixed
      // name: a file named after the device it belongs to, with
      // that suffix between two dots, is in shape (plan 145).
      expect(isCredentialEnvFileName('credentials.my-device.env'), isTrue);
      expect(isCredentialEnvFileName('credentials.phone2.env'), isTrue);
    });

    test('is case-insensitive', () {
      expect(isCredentialEnvFileName('Credentials.ENV'), isTrue);
      expect(isCredentialEnvFileName('CREDENTIALS.env'), isTrue);
    });

    test('rejects names outside the shape', () {
      expect(isCredentialEnvFileName('mycredentials.env'), isFalse);
      expect(isCredentialEnvFileName('credentials.txt'), isFalse);
      expect(isCredentialEnvFileName('credentials.env.bak'), isFalse);
      expect(isCredentialEnvFileName('credential.env'), isFalse);
      expect(isCredentialEnvFileName('env'), isFalse);
    });
  });

  group('selectCredentialCandidates', () {
    final valid = _envBytes(katSinkCert, katSinkPriv);

    test('lists a genuine pair under a matching name', () {
      final candidates = selectCredentialCandidates([
        _file('credentials.env', valid),
      ], validate: _validateWithTestAuthority);
      expect(candidates, hasLength(1));
      expect(candidates.single.name, 'credentials.env');
      expect(candidates.single.sizeBytes, valid.length);
      expect(bytesToHex(candidates.single.env.certificate), katSinkCert);
      expect(bytesToHex(candidates.single.env.privateKey), katSinkPriv);
    });

    test('lists a genuine pair under a device-suffixed name', () {
      final candidates = selectCredentialCandidates([
        _file('credentials.my-device.env', valid),
      ], validate: _validateWithTestAuthority);
      expect(candidates, hasLength(1));
      expect(candidates.single.name, 'credentials.my-device.env');
    });

    test('skips a file that does not parse', () {
      final candidates = selectCredentialCandidates([
        _file('credentials.env', Uint8List.fromList(utf8.encode('junk'))),
        _file('credentials2.env', Uint8List.fromList([0xff, 0xfe, 0x00])),
      ], validate: _validateWithTestAuthority);
      expect(candidates, isEmpty);
    });

    test('skips a parsed pair that fails validation', () {
      // The source device's key does not belong to the sink
      // certificate: parses fine, is not a genuine pair.
      final mismatched = _envBytes(katSinkCert, katSrcPriv);
      final candidates = selectCredentialCandidates([
        _file('credentials.env', mismatched),
      ], validate: _validateWithTestAuthority);
      expect(candidates, isEmpty);
    });

    test('skips a genuine pair under a non-matching name', () {
      final candidates = selectCredentialCandidates([
        _file('notes.env', valid),
        _file('credentials.txt', valid),
      ], validate: _validateWithTestAuthority);
      expect(candidates, isEmpty);
    });

    test('returns candidates in name order', () {
      final candidates = selectCredentialCandidates([
        _file('credentials-b.env', valid),
        _file('credentials-a.env', valid),
      ], validate: _validateWithTestAuthority);
      expect(candidates.map((c) => c.name), [
        'credentials-a.env',
        'credentials-b.env',
      ]);
    });

    test(
      'works with the credential store check the screen passes in',
      () async {
        final store = InMemoryCredentialStore(
          authorityKeys: [hexToBytes(katAuthPub)],
        );
        final candidates = selectCredentialCandidates(
          [_file('credentials.env', valid)],
          validate: (env) => store.validates(
            certificate: env.certificate,
            privateKey: env.privateKey,
          ),
        );
        expect(candidates, hasLength(1));
        // And the same store accepts the listed pair at save time:
        // the listing and the save cannot disagree.
        await store.save(
          certificate: candidates.single.env.certificate,
          privateKey: candidates.single.env.privateKey,
        );
        expect(await store.hasCredentials, isTrue);
      },
    );
  });
}
