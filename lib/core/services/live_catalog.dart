/// LiveCatalogService implementation (plan 39): a DIDL walk of
/// the DMS LiveTuner tree — the band containers under
/// `0/video/LiveTuner`, then each band's channel items — over
/// the same ContentDirectory Browse the recordings complement
/// uses. No SOAP action is involved: X_GetLiveChList returns
/// terrestrial service ids only and no programme information
/// (live survey, 2026-11-17).
library;

import '../models/live_channel.dart';
import '../parsing/didl.dart';
import 'interfaces.dart';

class DlnaLiveCatalogService implements LiveCatalogService {
  DlnaLiveCatalogService({required this._metadata});

  final MetadataService _metadata;

  @override
  Future<List<LiveBand>> listLiveChannels() async {
    final root = await _metadata.browse(MetadataService.liveTunerContainer);
    final bands = <LiveBand>[];
    for (final container in root.containers) {
      final doc = await _metadata.browse(container.id);
      bands.add(
        LiveBand(
          containerId: container.id,
          title: container.title,
          channels: [
            for (final item in doc.items) liveChannelFromDidl(item),
          ],
        ),
      );
    }
    return bands;
  }
}
