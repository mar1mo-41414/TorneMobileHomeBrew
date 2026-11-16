/// RegistrationService implementation (plan 5.2 / 11.5).
///
/// Flow: `status/networkIfInfoGet` (no auth) -> derive the PIN from
/// the MAC address -> `config/PINVerify` (POST + token, empty body).
/// The PIN itself is never sent and never stored; only the MAC (its
/// derivation source) is kept in the registration record.
library;

import 'package:http/http.dart' as http;

import '../endpoints.dart';
import '../errors.dart';
import '../models/device.dart';
import '../token.dart';
import '../transport/webapi_transport.dart';
import 'interfaces.dart';

class WebApiRegistrationService implements RegistrationService {
  WebApiRegistrationService({http.Client? client}) : _client = client; // ignore: prefer_initializing_formals - nullable pass-through, formal would change the public type

  final http.Client? _client;

  @override
  Future<RegisteredNasne> register(NasneDevice device) async {
    final plain = WebApiTransport(device.host, client: _client);
    final netJson = await plain.getJson(WebApiEndpoints.networkIfInfoGet);
    final network = NetworkInfo.fromJson(netJson);
    final tokens = TokenProvider(TokenProvider.derivePin(network.macAddr));
    final authed =
        WebApiTransport(device.host, client: _client, tokenProvider: tokens);
    // Throws NasneError (webapi/http/unreachable) when verification fails.
    await authed.postJson(WebApiEndpoints.pinVerify);
    return RegisteredNasne(
      host: device.host,
      udn: device.udn,
      friendlyName: device.friendlyName,
      macAddr: network.macAddr,
      registeredAt: DateTime.now(),
    );
  }

  @override
  Future<bool> verify(RegisteredNasne registration) async {
    final authed = WebApiTransport(
      registration.host,
      client: _client,
      tokenProvider: registration.tokenProvider,
    );
    try {
      await authed.postJson(WebApiEndpoints.pinVerify);
      return true;
    } on NasneError catch (e) {
      // A rejection means the PIN/token no longer matches; a
      // reachability failure is not a verification result.
      if (e.category == NasneErrorCategory.webapi ||
          e.category == NasneErrorCategory.http) {
        return false;
      }
      rethrow;
    }
  }
}
