/// xsrs document parsing and building (plan 12.3 / 12.5).
///
/// xsrs is the XML vocabulary carried inside the `Result` / `Elements`
/// strings of the X_ScheduledRecording actions. An xsrs document is a
/// flat list of `item` elements; each item has an `id` attribute and
/// child elements whose text and attributes carry the fields.
library;

import 'package:xml/xml.dart';

import '../broadcast_text.dart';
import '../errors.dart';
import '../models/schedule.dart';
import '../models/title.dart';
import '../time_util.dart';
import '../transport/xml_util.dart';

/// One parsed xsrs `item`.
class XsrsItem {
  const XsrsItem({
    required this.id,
    required this.fields,
    required this.attributes,
  });

  final String id;

  /// Child element local name -> text content.
  final Map<String, String> fields;

  /// Child element local name -> (attribute name -> value).
  final Map<String, Map<String, String>> attributes;

  String? operator [](String name) => fields[name];

  String? attribute(String element, String name) => attributes[element]?[name];
}

/// Parses an xsrs document string into its items.
List<XsrsItem> parseXsrsItems(String xmlText, String source) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlText);
  } catch (e) {
    throw NasneError.parse(source, cause: e);
  }
  final root = doc.rootElement;
  if (root.name.local != 'xsrs') {
    throw NasneError.parse(source, cause: 'root element is not <xsrs>');
  }
  final items = <XsrsItem>[];
  for (final item in childElements(root, 'item')) {
    final fields = <String, String>{};
    final attributes = <String, Map<String, String>>{};
    for (final child in item.childElements) {
      fields[child.name.local] = child.innerText;
      if (child.attributes.isNotEmpty) {
        attributes[child.name.local] = {
          for (final a in child.attributes) a.name.local: a.value,
        };
      }
    }
    items.add(XsrsItem(
      id: item.getAttribute('id') ?? '',
      fields: fields,
      attributes: attributes,
    ));
  }
  return items;
}

/// Wraps item XML in an xsrs document (the `Elements` argument form).
String buildXsrsDocument(String itemsXml) {
  return '<?xml version="1.0"?>'
      '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/">'
      '$itemsXml</xsrs>';
}

int _intField(XsrsItem item, String name, String source,
    {int fallback = 0}) {
  final text = item[name];
  if (text == null) return fallback;
  final value = int.tryParse(text.trim());
  if (value == null) {
    throw NasneError.parse(source, cause: '"$name" is not an integer: $text');
  }
  return value;
}

ScheduleChannel _channelOf(XsrsItem item, String source) {
  final text = item['scheduledChannelID'];
  if (text == null) {
    throw NasneError.parse(source, cause: 'missing scheduledChannelID');
  }
  return ScheduleChannel(
    broadcastingType:
        int.tryParse(item.attribute('scheduledChannelID', 'broadcastingType') ?? '') ?? 2,
    channelType:
        int.tryParse(item.attribute('scheduledChannelID', 'channelType') ?? '') ?? 2,
    serviceId: ScheduleChannel.parseServiceId(text),
  );
}

/// Converts an xsrs item to a [RecordSchedule] (list and conflict
/// items share the shape; conflict items add `conflictID`).
RecordSchedule recordScheduleFromXsrs(XsrsItem item, {required String source}) {
  final start = parseNasneDateTime(item['scheduledStartDateTime']);
  if (start == null) {
    throw NasneError.parse(source, cause: 'bad scheduledStartDateTime');
  }
  return RecordSchedule(
    id: item.id,
    start: start,
    durationSeconds: _intField(item, 'scheduledDuration', source),
    conditionId: item['scheduledConditionID'] ?? '',
    channel: _channelOf(item, source),
    desiredQualityMode: _intField(item, 'desiredQualityMode', source),
    desiredMatchingId: item['desiredMatchingID'] ?? '',
    matchingIdType: item.attribute('desiredMatchingID', 'type'),
    reservationCreatorId: item['reservationCreatorID'] ?? '',
    priorityFlag: _intField(item, 'priorityFlag', source),
    recordDestinationId: item['recordDestinationID'] ?? '',
    title: normalizeBroadcastTextOrNull(item['title']),
    conflictId: item['conflictID'],
  );
}

/// Builds the full-template create item (plan 11.7: every field of
/// torne's template must be present; there is no title element).
String buildCreateItemXml(NewRecordSchedule s) {
  final channel = s.channel;
  return '<item id="">'
      '<scheduledStartDateTime>${formatNasneDateTime(s.start)}</scheduledStartDateTime>'
      '<scheduledDuration>${s.durationSeconds}</scheduledDuration>'
      '<scheduledConditionID>${escapeXmlText(s.conditionId)}</scheduledConditionID>'
      '<scheduledChannelID broadcastingType="${channel.broadcastingType}" '
      'channelType="${channel.channelType}">${channel.serviceIdHex}</scheduledChannelID>'
      '<desiredQualityMode>${s.desiredQualityMode}</desiredQualityMode>'
      '<desiredMatchingID type="SI_PROGRAMID">${s.desiredMatchingId}</desiredMatchingID>'
      '<reservationCreatorID>${escapeXmlText(s.reservationCreatorId)}</reservationCreatorID>'
      '<priorityFlag>${s.priorityFlag}</priorityFlag>'
      '<recordDestinationID>${escapeXmlText(s.recordDestinationId)}</recordDestinationID>'
      '</item>';
}

/// Builds the sparse update item (plan 12.5, rule fixed by the phase 1
/// update matrix): [ScheduleUpdate.priorityFlag] is always present —
/// the device requires it — alongside the fields being changed.
String buildUpdateItemXml(ScheduleUpdate u) {
  final b = StringBuffer('<item id="${escapeXmlAttribute(u.id)}">');
  if (u.conditionId != null) {
    b.write('<scheduledConditionID>${escapeXmlText(u.conditionId!)}</scheduledConditionID>');
  }
  if (u.desiredQualityMode != null) {
    b.write('<desiredQualityMode>${u.desiredQualityMode}</desiredQualityMode>');
  }
  b.write('<priorityFlag>${u.priorityFlag}</priorityFlag>');
  if (u.recordDestinationId != null) {
    b.write('<recordDestinationID>${escapeXmlText(u.recordDestinationId!)}</recordDestinationID>');
  }
  b.write('</item>');
  return b.toString();
}

/// Converts an xsrs item to a [RecordedTitle] (XSRS side only; the
/// DIDL complement is merged by TitleCatalogService).
RecordedTitle recordedTitleFromXsrs(XsrsItem item, {required String source}) {
  final lastPlayback = item['lastPlaybackTime'];
  final duration = item['scheduledDuration'] == null
      ? null
      : _intField(item, 'scheduledDuration', source);
  return RecordedTitle(
    id: item.id,
    title: normalizeBroadcastText(item['title'] ?? ''),
    scheduledStart: parseNasneDateTime(item['scheduledStartDateTime']),
    scheduledDurationSeconds: duration,
    channel: item['scheduledChannelID'] == null
        ? null
        : _channelOf(item, source),
    desiredQualityMode: item['desiredQualityMode'] == null
        ? null
        : _intField(item, 'desiredQualityMode', source),
    genreId: item['genreID'],
    genreType: int.tryParse(item.attribute('genreID', 'type') ?? ''),
    reservationCreatorId: item['reservationCreatorID'],
    protectFlag: item['titleProtectFlag'] == '1',
    newFlag: item['titleNewFlag'] == '1',
    recordingFlag: item['recordingFlag'] == '1',
    recordDestinationId: item['recordDestinationID'],
    recordSizeRaw: item['recordSize'] == null
        ? null
        : int.tryParse(item['recordSize']!.trim()),
    lastPlaybackTime: parseNasneDateTime(lastPlayback),
    resumePointSeconds:
        int.tryParse(item.attribute('lastPlaybackTime', 'resumePoint') ?? ''),
  );
}
