/// ScheduleService implementation over UPnP SOAP XSRS (plan 12.3).
library;

import '../endpoints.dart';
import '../errors.dart';
import '../models/schedule.dart';
import '../parsing/xsrs.dart';
import '../transport/soap_transport.dart';
import 'interfaces.dart';

class SoapScheduleService implements ScheduleService {
  SoapScheduleService({
    required this._soap,
    required this._controlUrl,
  });

  final SoapTransport _soap;
  final Uri _controlUrl;

  static const String _serviceType =
      'urn:schemas-xsrs-org:service:X_ScheduledRecording:2';

  Future<SoapResponse> _call(String action,
      [Map<String, String> args = const {}]) {
    SoapServices.scheduledRecording.action(action); // validates the name
    return _soap.call(
      controlUrl: _controlUrl,
      serviceType: _serviceType,
      action: action,
      args: args,
    );
  }

  Map<String, String> _listArgs(int startingIndex, int requestedCount) => {
        'SearchCriteria': '',
        'Filter': '*',
        'StartingIndex': '$startingIndex',
        'RequestedCount': '$requestedCount',
        'SortCriteria': '',
      };

  @override
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  }) async {
    final resp = await _call(
        'X_GetRecordScheduleList', _listArgs(startingIndex, requestedCount));
    final result = resp.result;
    if (result == null) {
      throw NasneError.parse('soap:X_GetRecordScheduleList',
          cause: 'missing Result');
    }
    return [
      for (final item in parseXsrsItems(result, 'soap:X_GetRecordScheduleList'))
        recordScheduleFromXsrs(item, source: 'soap:X_GetRecordScheduleList'),
    ];
  }

  @override
  Future<String> createSchedule(NewRecordSchedule schedule) async {
    final elements = buildXsrsDocument(buildCreateItemXml(schedule));
    final resp = await _call('X_CreateRecordSchedule', {'Elements': elements});
    final rawId = resp.values['RecordScheduleID'];
    if (rawId == null || rawId.isEmpty) {
      throw NasneError.parse('soap:X_CreateRecordSchedule',
          cause: 'missing RecordScheduleID in response');
    }
    // The response form carries a literal "0x" prefix over the decimal
    // list id and fails deletion with 803 (plan 11.7); keep only the
    // normalised form.
    return normalizeScheduleId(rawId);
  }

  @override
  Future<void> updateSchedule(ScheduleUpdate update) async {
    if (update.isEmpty) {
      throw NasneError.validation(
          'soap:X_UpdateRecordSchedule', 'update has no fields');
    }
    final elements = buildXsrsDocument(buildUpdateItemXml(update));
    await _call('X_UpdateRecordSchedule', {'Elements': elements});
  }

  @override
  Future<void> deleteSchedule(String id) async {
    await _call('X_DeleteRecordSchedule', {'RecordScheduleID': id});
  }

  @override
  Future<List<RecordSchedule>> checkConflicts(
      NewRecordSchedule candidate) async {
    final elements = buildXsrsDocument(buildCreateItemXml(candidate));
    try {
      final resp = await _call('X_GetConflictList', {'Elements': elements});
      final result = resp.result;
      if (result == null) return const [];
      return [
        for (final item in parseXsrsItems(result, 'soap:X_GetConflictList'))
          recordScheduleFromXsrs(item, source: 'soap:X_GetConflictList'),
      ];
    } on NasneError catch (e) {
      // Measured quirk (phase 1 re-confirmation, plan 12.3): with zero
      // reservations on the device, X_GetConflictList answers a SOAP
      // Fault (HTTP 500, UPnP errorCode 402 "Action X_GetConflictList
      // failed") for a well-formed candidate, instead of an empty
      // list. Rule: on a Fault from this action, verify emptiness via
      // the list; empty means "no conflicts", otherwise the Fault is
      // genuine and propagates.
      if (e.category != NasneErrorCategory.soapFault) rethrow;
      final existing = await listSchedules();
      if (existing.isEmpty) return const [];
      rethrow;
    }
  }
}
