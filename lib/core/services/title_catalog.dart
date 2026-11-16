/// TitleCatalogService implementation (plan 12.1 / 12.5).
///
/// Primary source is the XSRS title list; counts come from the
/// WebAPI count endpoints; the DIDL complement (copy count, res list,
/// descriptions) is joined by title id inside this implementation —
/// callers only see the merged [RecordedTitle].
library;

import '../endpoints.dart';
import '../errors.dart';
import '../models/title.dart';
import '../parsing/xsrs.dart';
import '../transport/soap_transport.dart';
import '../transport/webapi_transport.dart';
import 'interfaces.dart';

class SoapTitleCatalogService implements TitleCatalogService {
  SoapTitleCatalogService({
    required this._soap,
    required Uri xsrsControlUrl,
    required this._webApi,
    required this._metadata,
  }) : _controlUrl = xsrsControlUrl;

  final SoapTransport _soap;
  final Uri _controlUrl;
  final WebApiTransport _webApi;
  final MetadataService _metadata;

  static const String _serviceType =
      'urn:schemas-xsrs-org:service:X_ScheduledRecording:2';

  @override
  Future<List<RecordedTitle>> listTitles({bool withMetadata = true}) async {
    final resp = await _soap.call(
      controlUrl: _controlUrl,
      serviceType: _serviceType,
      action: 'X_GetTitleList',
      args: const {
        'SearchCriteria': '',
        'Filter': '*',
        'StartingIndex': '0',
        'RequestedCount': '0',
        'SortCriteria': '',
      },
    );
    final result = resp.result;
    if (result == null) {
      throw NasneError.parse('soap:X_GetTitleList', cause: 'missing Result');
    }
    final titles = [
      for (final item in parseXsrsItems(result, 'soap:X_GetTitleList'))
        recordedTitleFromXsrs(item, source: 'soap:X_GetTitleList'),
    ];
    if (!withMetadata || titles.isEmpty) return titles;

    final didl = await _metadata.browse(MetadataService.allRecordingsContainer);
    final byTitleId = {
      for (final item in didl.items)
        if (item.titleId != null) item.titleId!: item,
    };
    return [
      for (final title in titles)
        if (byTitleId[title.id] case final match?)
          title.withDidl(
            description: match.description,
            longDescription: match.longDescription,
            channelName: match.channelName,
            copyCountRemaining: match.copyCountRemaining,
            res: match.res,
          )
        else
          title,
    ];
  }

  @override
  Future<int> countTitles() async {
    final json = await _webApi.getJson(WebApiEndpoints.recordedContentCountGet);
    final count = json['count'];
    if (count is! num) {
      throw NasneError.parse('webapi:/recorded/recordedContentCountGet',
          cause: 'missing count');
    }
    return count.toInt();
  }

  @override
  Future<int> maxTitles() async {
    final json =
        await _webApi.getJson(WebApiEndpoints.recordedContentMaxCountGet);
    final count = json['count'];
    if (count is! num) {
      throw NasneError.parse('webapi:/recorded/recordedContentMaxCountGet',
          cause: 'missing count');
    }
    return count.toInt();
  }
}
