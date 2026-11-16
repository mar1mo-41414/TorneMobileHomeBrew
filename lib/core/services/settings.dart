/// SettingsService implementation (plan 12.1).
///
/// Reads are plain GETs; writes go through the token-authenticated
/// POST path of the transport. The transport must have been built
/// with the registration's TokenProvider for the writes to succeed.
library;

import '../endpoints.dart';
import '../json_util.dart';
import '../transport/webapi_transport.dart';
import 'interfaces.dart';

class WebApiSettingsService implements SettingsService {
  WebApiSettingsService(this._transport);

  final WebApiTransport _transport;

  @override
  Future<String> getBoxName() async {
    final json = await _transport.getJson(WebApiEndpoints.boxNameGet);
    return optString(json, 'name') ?? '';
  }

  @override
  Future<int> getMobileBitrate() async {
    final json = await _transport.getJson(WebApiEndpoints.mobileBitrateInfoGet);
    return optInt(json, 'bitrateInfo') ?? 0;
  }

  @override
  Future<void> setBoxName(String name) async {
    await _transport.postJson(
      WebApiEndpoints.boxNameSet,
      form: {'name': name},
    );
  }

  @override
  Future<void> setMobileBitrate(int bitrateInfo) async {
    await _transport.postJson(
      WebApiEndpoints.mobileBitrateInfoSet,
      form: {'bitrateInfo': '$bitrateInfo'},
    );
  }
}
