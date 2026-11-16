/// MetadataService implementation: ContentDirectory Browse (plan 12.1).
library;

import '../endpoints.dart';
import '../errors.dart';
import '../models/didl.dart';
import '../parsing/didl.dart';
import '../transport/soap_transport.dart';
import 'interfaces.dart';

class DlnaMetadataService implements MetadataService {
  DlnaMetadataService({
    required this._soap,
    required this._controlUrl,
  });

  final SoapTransport _soap;
  final Uri _controlUrl;

  static const String _serviceType =
      'urn:schemas-upnp-org:service:ContentDirectory:1';

  @override
  Future<DidlDocument> browse(String objectId) async {
    SoapServices.contentDirectory.action('Browse');
    final resp = await _soap.call(
      controlUrl: _controlUrl,
      serviceType: _serviceType,
      action: 'Browse',
      args: {
        'ObjectID': objectId,
        'BrowseFlag': 'BrowseDirectChildren',
        'Filter': '*',
        'StartingIndex': '0',
        // 0 = as many as available (measured form, plan 11.8).
        'RequestedCount': '0',
        'SortCriteria': '',
      },
    );
    final result = resp.result;
    if (result == null) {
      throw NasneError.parse('soap:Browse', cause: 'missing Result');
    }
    return parseDidl(result, 'soap:Browse');
  }
}
