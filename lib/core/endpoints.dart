/// Endpoint definition tables (plan sections 5.0 principle 3, 12.1, 12.2).
///
/// Only endpoints whose behaviour was measured against the real device
/// in phase 0 (plan section 11) are listed here. The tables manage
/// "where it goes, in what form, and whether it needs a token"; the
/// shape of the payload itself is the job of the typed models.
library;

/// Response payload kind of a WebAPI endpoint.
enum ApiResponseKind { json, binary }

/// One WebAPI (JSON, port 64210) endpoint definition.
class WebApiEndpoint {
  const WebApiEndpoint(
    this.path, {
    this.method = 'GET',
    this.requiredParams = const [],
    this.authRequired = false,
    this.responseKind = ApiResponseKind.json,
  });

  /// Path including the leading slash, e.g. `/status/boxNameGet`.
  /// This exact string is also the path component of the token input.
  final String path;

  final String method;

  /// Query / form parameters that must be supplied (measured, plan 11.4).
  final List<String> requiredParams;

  /// Whether an X-DTVToken header is required (POST Set operations).
  final bool authRequired;

  final ApiResponseKind responseKind;

  @override
  String toString() => 'WebApiEndpoint($method $path)';
}

/// WebAPI endpoint definitions, measured in phase 0 (plan 11.4 / 11.5).
abstract final class WebApiEndpoints {
  // -- status: reads (GET, no auth) --
  static const softwareVersionGet = WebApiEndpoint('/status/softwareVersionGet');
  static const updateCheck = WebApiEndpoint('/status/updateCheck');
  static const isFinishSetup = WebApiEndpoint('/status/isFinishSetup');
  static const boxNameGet = WebApiEndpoint('/status/boxNameGet');
  static const currDateGet = WebApiEndpoint('/status/currDateGet');
  static const areaInfoGet = WebApiEndpoint('/status/areaInfoGet');
  static const channelListGet = WebApiEndpoint(
    '/status/channelListGet',
    requiredParams: ['broadcastingType'],
  );
  static const hddListGet = WebApiEndpoint('/status/HDDListGet');
  static const hddInfoGet = WebApiEndpoint(
    '/status/HDDInfoGet',
    requiredParams: ['id'],
  );
  static const bcasInfoGet = WebApiEndpoint('/status/BCASInfoGet');
  static const networkIfInfoGet = WebApiEndpoint('/status/networkIfInfoGet');
  static const recNgListGet = WebApiEndpoint('/status/recNgListGet');
  static const liveStreamStatusListGet =
      WebApiEndpoint('/status/liveStreamStatusListGet');
  static const dtcpipClientListGet =
      WebApiEndpoint('/status/dtcpipClientListGet');
  static const parentalRatingInfoGet =
      WebApiEndpoint('/status/parentalRatingInfoGet');
  static const mobileBitrateInfoGet =
      WebApiEndpoint('/status/mobileBitrateInfoGet');
  static const dmsStreamStopReasonListGet =
      WebApiEndpoint('/status/dmsStreamStopReasonListGet');
  static const requestClientInfoGet =
      WebApiEndpoint('/status/requestClientInfoGet');
  static const epgVersionInfoGet = WebApiEndpoint(
    '/status/EPGVersionInfoGet',
    requiredParams: ['broadcastingType'],
    responseKind: ApiResponseKind.binary,
  );

  // -- recorded: counts (GET, no auth) --
  static const recordedContentCountGet =
      WebApiEndpoint('/recorded/recordedContentCountGet');
  static const recordedContentMaxCountGet =
      WebApiEndpoint('/recorded/recordedContentMaxCountGet');

  // -- recorded: binary maps (GET, no auth) --
  static const thumbnailMapGet = WebApiEndpoint(
    '/recorded/thumbnailMapGet',
    requiredParams: ['id'],
    responseKind: ApiResponseKind.binary,
  );
  static const pmtMapGet = WebApiEndpoint(
    '/recorded/PMTMapGet',
    requiredParams: ['id'],
    responseKind: ApiResponseKind.binary,
  );
  static const seMapDataGet = WebApiEndpoint(
    '/recorded/SEMapDataGet',
    requiredParams: ['id'],
    responseKind: ApiResponseKind.binary,
  );

  // -- chEpg (binary) --
  static const channelLogoDataGet = WebApiEndpoint(
    '/chEpg/channelLogoDataGet',
    requiredParams: ['broadcastingType'],
    responseKind: ApiResponseKind.binary,
  );

  /// Full programme guide (plan 21): POST with the EPG version
  /// table repeated as an application/binary body; token required.
  static const epgGet = WebApiEndpoint(
    '/chEpg/EPGGet',
    method: 'POST',
    authRequired: true,
    responseKind: ApiResponseKind.binary,
  );

  // -- config: progress reads (GET, no auth) --
  static const internalHddInitializeProgressGet =
      WebApiEndpoint('/config/internalHDDInitializeProgressGet');
  static const hddRegisterProgressGet = WebApiEndpoint(
    '/config/HDDRegisterProgressGet',
    requiredParams: ['id'],
  );
  static const channelScanProgressGet = WebApiEndpoint(
    '/config/channelScanProgressGet',
    requiredParams: ['broadcastingType'],
  );

  // -- config: writes / verification (POST, token required) --
  static const pinVerify = WebApiEndpoint(
    '/config/PINVerify',
    method: 'POST',
    authRequired: true,
  );
  static const boxNameSet = WebApiEndpoint(
    '/config/boxNameSet',
    method: 'POST',
    requiredParams: ['name'],
    authRequired: true,
  );
  static const mobileBitrateInfoSet = WebApiEndpoint(
    '/config/mobileBitrateInfoSet',
    method: 'POST',
    requiredParams: ['bitrateInfo'],
    authRequired: true,
  );

  static const List<WebApiEndpoint> all = [
    softwareVersionGet,
    updateCheck,
    isFinishSetup,
    boxNameGet,
    currDateGet,
    areaInfoGet,
    channelListGet,
    hddListGet,
    hddInfoGet,
    bcasInfoGet,
    networkIfInfoGet,
    recNgListGet,
    liveStreamStatusListGet,
    dtcpipClientListGet,
    parentalRatingInfoGet,
    mobileBitrateInfoGet,
    dmsStreamStopReasonListGet,
    requestClientInfoGet,
    epgVersionInfoGet,
    recordedContentCountGet,
    recordedContentMaxCountGet,
    thumbnailMapGet,
    pmtMapGet,
    seMapDataGet,
    channelLogoDataGet,
    epgGet,
    internalHddInitializeProgressGet,
    hddRegisterProgressGet,
    channelScanProgressGet,
    pinVerify,
    boxNameSet,
    mobileBitrateInfoSet,
  ];
}

/// How a SOAP action's `Result` value must be interpreted.
enum SoapResultKind {
  /// No Result value (scalar out-arguments only).
  none,

  /// Result holds an xsrs document (schedule / title lists).
  xsrs,

  /// Result holds a DIDL-Lite document (ContentDirectory Browse).
  didl,
}

/// One UPnP SOAP action definition.
class SoapActionDef {
  const SoapActionDef(this.name, {this.resultKind = SoapResultKind.none});

  final String name;
  final SoapResultKind resultKind;
}

/// One UPnP service definition: URN, control URL resolution, actions.
class SoapServiceDef {
  const SoapServiceDef({
    required this.serviceType,
    required this.defaultPort,
    required this.fallbackControlPaths,
    required this.actions,
  });

  /// The UPnP serviceType URN, used both for description lookup and as
  /// the SOAPAction namespace.
  final String serviceType;

  /// Port used when a control URL has to be synthesised from fallbacks.
  final int defaultPort;

  /// Control URL paths tried (in order) when the device description
  /// does not yield one (measured forms, plan 11.7 / 11.8).
  final List<String> fallbackControlPaths;

  final Map<String, SoapActionDef> actions;

  SoapActionDef action(String name) {
    final def = actions[name];
    if (def == null) {
      throw ArgumentError('unknown action $name for $serviceType');
    }
    return def;
  }
}

/// SOAP service definitions, measured in phase 0 (plan 11.7 / 11.8).
abstract final class SoapServices {
  static const scheduledRecording = SoapServiceDef(
    serviceType: 'urn:schemas-xsrs-org:service:X_ScheduledRecording:2',
    defaultPort: 64230,
    fallbackControlPaths: ['/XSRS', '/xsrs/control/X_ScheduledRecording'],
    actions: {
      'X_GetRecordScheduleList':
          SoapActionDef('X_GetRecordScheduleList', resultKind: SoapResultKind.xsrs),
      'X_GetTitleList':
          SoapActionDef('X_GetTitleList', resultKind: SoapResultKind.xsrs),
      'X_GetConflictList':
          SoapActionDef('X_GetConflictList', resultKind: SoapResultKind.xsrs),
      'X_CreateRecordSchedule': SoapActionDef('X_CreateRecordSchedule'),
      'X_UpdateRecordSchedule': SoapActionDef('X_UpdateRecordSchedule'),
      'X_DeleteRecordSchedule': SoapActionDef('X_DeleteRecordSchedule'),
    },
  );

  static const pvrControl = SoapServiceDef(
    serviceType: 'urn:schemas-s-bras-org:service:X_PvrControl:1',
    defaultPort: 64230,
    fallbackControlPaths: ['/X_PvrControl'],
    actions: {
      'X_GetFirmwareVersion': SoapActionDef('X_GetFirmwareVersion'),
      'X_GetLiveChList': SoapActionDef('X_GetLiveChList'),
      'X_GetTitleInfo': SoapActionDef('X_GetTitleInfo'),
      'X_GetTitleDetail': SoapActionDef('X_GetTitleDetail'),
    },
  );

  static const contentDirectory = SoapServiceDef(
    serviceType: 'urn:schemas-upnp-org:service:ContentDirectory:1',
    defaultPort: 58888,
    fallbackControlPaths: ['/MediaServer_ContentDirectory/control'],
    actions: {
      'Browse': SoapActionDef('Browse', resultKind: SoapResultKind.didl),
    },
  );

  static const List<SoapServiceDef> all = [
    scheduledRecording,
    pvrControl,
    contentDirectory,
  ];
}

/// Broadcasting type correspondences across the three notations
/// (plan 12.5): WebAPI numeric `broadcastingType`, SOAP string
/// `BroadcastType`, and the xsrs `scheduledChannelID` attributes.
///
/// Only the terrestrial row was measured in phase 0 (WebAPI
/// `broadcastingType=2`; 0/1 were rejected with 400 on this firmware,
/// and `X_GetLiveChList` used the string `"DTT"`).
abstract final class BroadcastingTypes {
  static const int terrestrial = 2;
  static const String terrestrialSoapName = 'DTT';
}
