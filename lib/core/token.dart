/// X-DTVToken computation (plan sections 5.3 / 11.5 / 12.4).
///
/// The formula was confirmed against the real device in phase 0:
///   PIN   = the last 3 octets of the device MAC address
///           (`status/networkIfInfoGet` -> `macAddr`, colons removed,
///           characters from index 6 on, notation as returned).
///   token = base64( SHA1( PIN + path + body[0..256] ) )
/// where `path` includes the leading slash (e.g. `/config/PINVerify`)
/// and `body` is the request body string (empty for PINVerify).
///
/// This class is a pure function holder so it can be unit-tested against
/// known values; it never leaves the transport layer (plan 12.4).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

class TokenProvider {
  const TokenProvider(this.pin);

  /// The PIN derived from the registered device's MAC address.
  final String pin;

  /// Derives the PIN from a MAC address string as returned by
  /// `status/networkIfInfoGet` (e.g. `00:25:dc:58:da:f0` -> `58daf0`).
  static String derivePin(String macAddr) {
    final stripped = macAddr.replaceAll(':', '');
    if (stripped.length < 12) {
      throw ArgumentError.value(macAddr, 'macAddr', 'unexpected MAC format');
    }
    return stripped.substring(6);
  }

  /// Computes the X-DTVToken header value for [path] and [body].
  String tokenFor(String path, [String body = '']) =>
      computeToken(pin, path, body);

  /// Computes the X-DTVToken header value for [path] and a binary
  /// [body] (plan 21: `chEpg/EPGGet`). The hashed body prefix is
  /// the raw bytes, exactly as sent.
  String tokenForBytes(String path, List<int> body) =>
      computeTokenBytes(pin, path, body);

  /// Stateless form of [tokenFor], exposed for known-value tests.
  static String computeToken(String pin, String path, String body) {
    final head = body.length > 256 ? body.substring(0, 256) : body;
    final digest = sha1.convert(utf8.encode('$pin$path$head'));
    return base64.encode(digest.bytes);
  }

  /// Stateless form of [tokenForBytes].
  static String computeTokenBytes(String pin, String path, List<int> body) {
    final head = body.length > 256 ? body.sublist(0, 256) : body;
    final digest = sha1.convert([...utf8.encode('$pin$path'), ...head]);
    return base64.encode(digest.bytes);
  }
}
