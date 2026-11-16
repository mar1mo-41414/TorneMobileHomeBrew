/// Channel model (plan 12.5), from `status/channelListGet`.
library;

import '../json_util.dart';

/// One channel of a broadcasting type's channel list.
///
/// The channel identity used when creating a reservation is
/// [serviceId]; the notations of the three transports (WebAPI numeric
/// broadcastingType, SOAP string BroadcastType, xsrs hex serviceId)
/// are reconciled here and in the endpoint definition tables.
class Channel {
  const Channel({
    required this.broadcastingType,
    required this.networkId,
    required this.transportStreamId,
    required this.serviceId,
    required this.serviceType,
    required this.channelNumber,
    required this.serviceName,
    this.branchNumber = 0,
    this.serviceProviderName,
    this.freqChannelNo,
    this.remoteControlKeyId,
    this.contract = false,
  });

  /// WebAPI numeric broadcasting type (terrestrial = 2, measured).
  final int broadcastingType;
  final int networkId;
  final int transportStreamId;
  final int serviceId;
  final int serviceType;
  final int channelNumber;
  final int branchNumber;
  final String serviceName;
  final String? serviceProviderName;

  /// Physical channel number, a string in the measured response.
  final String? freqChannelNo;
  final int? remoteControlKeyId;
  final bool contract;

  /// The xsrs notation of the service id (`0x%04x`, plan 11.7).
  String get serviceIdHex =>
      '0x${serviceId.toRadixString(16).padLeft(4, '0')}';

  factory Channel.fromJson(
    Map<String, dynamic> json, {
    required int broadcastingType,
  }) {
    const src = 'webapi:/status/channelListGet';
    return Channel(
      broadcastingType: broadcastingType,
      networkId: reqInt(json, 'networkId', src),
      transportStreamId: reqInt(json, 'transportStreamId', src),
      serviceId: reqInt(json, 'serviceId', src),
      serviceType: reqInt(json, 'serviceType', src),
      channelNumber: reqInt(json, 'channelNumber', src),
      branchNumber: optInt(json, 'branchNumber') ?? 0,
      serviceName: optString(json, 'serviceName') ?? '',
      serviceProviderName: optString(json, 'serviceProviderName'),
      freqChannelNo: optString(json, 'freqChannelNo'),
      remoteControlKeyId: optInt(json, 'remoteControlKeyId'),
      contract: flag(json, 'contract'),
    );
  }
}
