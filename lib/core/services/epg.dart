/// EPG (programme guide) service (plan 12.8 / 21).
///
/// The acquisition recipe, determined by measurement (plan 21):
/// fetch the binary version table from `status/EPGVersionInfoGet`,
/// send it back three times concatenated as the binary body of
/// `chEpg/EPGGet` (POST, Content-Type: application/binary,
/// X-DTVToken over the body), then deobfuscate (XOR 0x9d) and
/// inflate the response. One call returns the full guide for the
/// broadcasting type (8 days, all services, on the measured unit).
library;

import '../endpoints.dart';
import '../errors.dart';
import '../models/channel.dart';
import '../models/epg.dart';
import '../parsing/epg.dart';
import '../transport/webapi_transport.dart';

class WebApiEpgService {
  WebApiEpgService({required this._plain, required this._authed});

  final WebApiTransport _plain;
  final WebApiTransport _authed;

  /// Fetches and parses the full programme guide for
  /// [broadcastingType]. [channels] is the type's channel list
  /// (DeviceInfoService.listChannels); blocks are anchored on it.
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  ) async {
    final versionTable = await _plain.getBytes(
      WebApiEndpoints.epgVersionInfoGet,
      params: {'broadcastingType': '$broadcastingType'},
    );
    if (versionTable.isEmpty) {
      throw NasneError.parse('webapi:EPGVersionInfoGet',
          cause: 'empty version table');
    }
    // The measured acceptance rule needs the table repeated; three
    // copies put the body past the observed threshold with margin
    // (plan 21). The response is the full dataset, not a delta.
    final body = <int>[
      ...versionTable,
      ...versionTable,
      ...versionTable,
    ];
    final raw = await _authed.postBinary(
      WebApiEndpoints.epgGet,
      body: body,
    );
    final plain = inflateEpgResponse(raw);
    return parseEpgGuide(plain, channels,
        broadcastingType: broadcastingType);
  }

  /// Fetches the channel logos of [broadcastingType] as
  /// serviceId -> PNG bytes (services without a logo are absent).
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType) async {
    final raw = await _plain.getBytes(
      WebApiEndpoints.channelLogoDataGet,
      params: {'broadcastingType': '$broadcastingType'},
    );
    return parseChannelLogos(raw);
  }
}
