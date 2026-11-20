/// TitleCatalogService implementation (plan 12.1 / 12.5).
///
/// Primary source is the XSRS title list; counts come from the
/// WebAPI count endpoints; the DIDL complement (copy count, res list,
/// descriptions) is joined by title id inside this implementation —
/// callers only see the merged [RecordedTitle].
library;

import 'dart:typed_data';

import '../endpoints.dart';
import '../errors.dart';
import '../models/title.dart';
import '../parsing/thumbnail.dart';
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
            genre: match.genre,
            copyCountRemaining: match.copyCountRemaining,
            res: match.res,
          )
        else
          title,
    ];
  }

  @override
  Future<void> deleteTitle(String id) async {
    // X_DeleteTitle on the same XSRS service as the title list
    // (plan 86.3). The TitleID argument name follows the
    // service's measured ID naming (X_DeleteRecordSchedule
    // takes RecordScheduleID); a wrong name surfaces as a SOAP
    // Fault, never as a silent wrong deletion. Device
    // verification is pending (plan 86.3).
    await _soap.call(
      controlUrl: _controlUrl,
      serviceType: _serviceType,
      action: 'X_DeleteTitle',
      args: {'TitleID': id},
    );
  }

  @override
  Future<Uint8List?> fetchThumbnail(String id) async {
    // The thumbnail map's container layout is unmeasured
    // (plan 11.4 / 86.6): the image is located by magic bytes
    // inside whatever came back. Every failure — transport,
    // status, an unrecognised payload — is simply "no
    // thumbnail"; a missing picture must never break the list.
    try {
      final raw = await _webApi.getBytes(
        WebApiEndpoints.thumbnailMapGet,
        params: {'id': id},
      );
      return extractThumbnailImage(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> countTitles() async {
    final json = await _webApi.getJson(WebApiEndpoints.recordedContentCountGet);
    final count = json['count'];
    if (count is! num) {
      throw NasneError.parse(
        'webapi:/recorded/recordedContentCountGet',
        cause: 'missing count',
      );
    }
    return count.toInt();
  }

  @override
  Future<int> maxTitles() async {
    final json = await _webApi.getJson(
      WebApiEndpoints.recordedContentMaxCountGet,
    );
    final count = json['count'];
    if (count is! num) {
      throw NasneError.parse(
        'webapi:/recorded/recordedContentMaxCountGet',
        cause: 'missing count',
      );
    }
    return count.toInt();
  }
}
