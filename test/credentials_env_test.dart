/// Tests for the credentials.env parser (plan 67).
///
/// All values are the published known-answer dummies from
/// dtcp_kat.dart (test authority pair) — never real credentials.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

import 'dtcp_kat.dart';

void main() {
  final testAuthority = [hexToBytes(katAuthPub)];

  group('parseCredentialsEnv format handling', () {
    test('parses the plain two-line form', () {
      final env = parseCredentialsEnv(
        'PYDTCPIP_CERTIFICATE=$katSinkCert\n'
        'PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n',
      );
      expect(bytesToHex(env.certificate), katSinkCert);
      expect(bytesToHex(env.privateKey), katSinkPriv);
    });

    test('tolerates comments, blanks, CRLF, spacing and quoting', () {
      final env = parseCredentialsEnv(
        '# pydtcpip credentials\r\n'
        '; another comment\r\n'
        '\r\n'
        'export PYDTCPIP_CERTIFICATE = "${katSinkCert.toUpperCase()}"\r\n'
        "PYDTCPIP_PRIVATE_KEY='${katSinkPriv.toUpperCase()}' # inline\r\n"
        'UNRELATED_VARIABLE=whatever\n',
      );
      expect(bytesToHex(env.certificate), katSinkCert);
      expect(bytesToHex(env.privateKey), katSinkPriv);
    });

    test('tolerates a UTF-8 BOM at the start of the file', () {
      final env = parseCredentialsEnv(
        '\uFEFFPYDTCPIP_CERTIFICATE=$katSinkCert\n'
        'PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n',
      );
      expect(bytesToHex(env.certificate), katSinkCert);
      expect(bytesToHex(env.privateKey), katSinkPriv);
    });

    test('tolerates whitespace inside the hex value', () {
      final spaced = katSinkPriv.replaceAllMapped(
        RegExp(r'.{4}'),
        (m) => '${m.group(0)} ',
      );
      final env = parseCredentialsEnv(
        'PYDTCPIP_CERTIFICATE=$katSinkCert\n'
        'PYDTCPIP_PRIVATE_KEY=$spaced\n',
      );
      expect(bytesToHex(env.privateKey), katSinkPriv);
    });

    test('rejects a missing variable', () {
      expect(
        () => parseCredentialsEnv('PYDTCPIP_CERTIFICATE=$katSinkCert\n'),
        throwsA(isA<NasneError>()),
      );
      expect(
        () => parseCredentialsEnv('PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n'),
        throwsA(isA<NasneError>()),
      );
      expect(() => parseCredentialsEnv(''), throwsA(isA<NasneError>()));
    });

    test('rejects non-hex and odd-length values', () {
      expect(
        () => parseCredentialsEnv(
          'PYDTCPIP_CERTIFICATE=zz$katSinkCert\n'
          'PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n',
        ),
        throwsA(isA<NasneError>()),
      );
      expect(
        () => parseCredentialsEnv(
          'PYDTCPIP_CERTIFICATE=$katSinkCert\n'
          'PYDTCPIP_PRIVATE_KEY=${katSinkPriv}0\n',
        ),
        throwsA(isA<NasneError>()),
      );
    });

    test('rejects a line that is not an assignment', () {
      expect(
        () => parseCredentialsEnv(
          'PYDTCPIP_CERTIFICATE=$katSinkCert\n'
          'this is not an assignment\n'
          'PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n',
        ),
        throwsA(isA<NasneError>()),
      );
    });

    test('error messages never echo the values', () {
      try {
        parseCredentialsEnv(
          'PYDTCPIP_CERTIFICATE=${katSinkCert}zz\n'
          'PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n',
        );
        fail('expected a NasneError');
      } on NasneError catch (e) {
        expect('$e', isNot(contains(katSinkCert)));
        expect('$e', isNot(contains(katSinkPriv)));
      }
    });
  });

  group('handoff to the shared validation path', () {
    test('a parsed genuine pair saves through the credential store', () async {
      final env = parseCredentialsEnv(
        'PYDTCPIP_CERTIFICATE=$katSinkCert\n'
        'PYDTCPIP_PRIVATE_KEY=$katSinkPriv\n',
      );
      final store = InMemoryCredentialStore(authorityKeys: testAuthority);
      await store.save(
        certificate: env.certificate,
        privateKey: env.privateKey,
      );
      expect(await store.hasCredentials, isTrue);
      final loaded = await store.load();
      expect(loaded?.deviceId, katSinkId);
    });

    test('a parsed mismatched pair is rejected by the same validation', () {
      final env = parseCredentialsEnv(
        'PYDTCPIP_CERTIFICATE=$katSinkCert\n'
        'PYDTCPIP_PRIVATE_KEY=$katSrcPriv\n',
      );
      final store = InMemoryCredentialStore(authorityKeys: testAuthority);
      expect(
        () => store.save(
          certificate: env.certificate,
          privateKey: env.privateKey,
        ),
        throwsA(isA<NasneError>()),
      );
    });
  });
}
