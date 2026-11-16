/// Known-value tests for the X-DTVToken computation (plan 12.9 step 1).
///
/// The vectors were produced with the phase 0 formula
/// (base64(SHA1(PIN + path + body[0..256]))) using a synthetic MAC, and
/// the same formula was verified against the real device in phase 0
/// (PINVerify / boxNameSet, plan 11.5). No real device values are used.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/token.dart';

void main() {
  group('TokenProvider.derivePin', () {
    test('takes the last 3 octets, notation as returned', () {
      expect(TokenProvider.derivePin('00:11:22:33:44:55'), '334455');
      expect(TokenProvider.derivePin('00:25:dc:58:da:f0'), '58daf0');
    });

    test('rejects a malformed MAC', () {
      expect(() => TokenProvider.derivePin('00:11:22'), throwsArgumentError);
    });
  });

  group('TokenProvider.computeToken (known values)', () {
    test('PINVerify shape: empty body', () {
      expect(
        TokenProvider.computeToken('334455', '/config/PINVerify', ''),
        '9JOKWxjRn9ykWcZg64FM+gJC7Ik=',
      );
    });

    test('POST with a form body', () {
      expect(
        TokenProvider.computeToken(
            '334455', '/config/boxNameSet', 'name=nasne-test'),
        'y8gpxn3qdE7CFJBmkAJaD7QHPlM=',
      );
    });

    test('body is truncated to its first 256 characters', () {
      final long = 'x' * 300;
      expect(
        TokenProvider.computeToken('334455', '/config/boxNameSet', long),
        'hR9VvweodV3XWNUVFtLXy857MUc=',
      );
      expect(
        TokenProvider.computeToken('334455', '/config/boxNameSet', long),
        TokenProvider.computeToken(
            '334455', '/config/boxNameSet', 'x' * 256),
      );
    });

    test('instance form matches the static form', () {
      const provider = TokenProvider('334455');
      expect(provider.tokenFor('/config/PINVerify'),
          TokenProvider.computeToken('334455', '/config/PINVerify', ''));
    });
  });
}
