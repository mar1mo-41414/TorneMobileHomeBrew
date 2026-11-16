/// DIDL-Lite parsing (plan 11.8 / 12.5).
library;

import 'package:xml/xml.dart';

import '../errors.dart';
import '../models/didl.dart';
import '../models/title.dart';
import '../transport/xml_util.dart';

/// Parses a DIDL-Lite document string (the `Result` of a Browse).
DidlDocument parseDidl(String xmlText, String source) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlText);
  } catch (e) {
    throw NasneError.parse(source, cause: e);
  }
  final root = doc.rootElement;
  if (root.name.local != 'DIDL-Lite') {
    throw NasneError.parse(source, cause: 'root element is not <DIDL-Lite>');
  }

  final containers = <DidlContainer>[];
  for (final el in childElements(root, 'container')) {
    containers.add(DidlContainer(
      id: el.getAttribute('id') ?? '',
      parentId: el.getAttribute('parentID') ?? '',
      title: childText(el, 'title') ?? '',
      childCount: int.tryParse(el.getAttribute('childCount') ?? ''),
    ));
  }

  final items = <DidlItem>[];
  for (final el in childElements(root, 'item')) {
    items.add(_parseItem(el));
  }
  return DidlDocument(containers: containers, items: items);
}

DidlItem _parseItem(XmlElement el) {
  final properties = <String, String>{};
  final resList = <TitleRes>[];
  String? description;
  String? longDescription;
  String? channelName;
  int? channelNr;
  int? cogCount;

  for (final child in el.childElements) {
    final qualified = child.name.qualified;
    final text = child.innerText;
    switch (child.name.local) {
      case 'res':
        resList.add(_parseRes(child));
      case 'description':
        description = text;
        properties[qualified] = text;
      case 'longDescription':
        // Two entries exist (synopsis / credits); keep both, joined.
        longDescription =
            longDescription == null ? text : '$longDescription\n$text';
        properties.putIfAbsent(qualified, () => text);
      case 'channelName':
        channelName = text;
        properties[qualified] = text;
      case 'channelNr':
        channelNr = int.tryParse(text.trim());
        properties[qualified] = text;
      case 'COGCount':
        cogCount = int.tryParse(text.trim());
        properties[qualified] = text;
      default:
        properties.putIfAbsent(qualified, () => text);
    }
  }

  return DidlItem(
    id: el.getAttribute('id') ?? '',
    parentId: el.getAttribute('parentID') ?? '',
    title: childText(el, 'title') ?? '',
    date: properties['dc:date'],
    description: description,
    longDescription: longDescription,
    channelName: channelName,
    channelNr: channelNr,
    copyCountRemaining: cogCount,
    res: resList,
    properties: properties,
  );
}

TitleRes _parseRes(XmlElement el) {
  final url = el.innerText.trim();
  final protocolInfo = el.getAttribute('protocolInfo') ?? '';

  String? protocolParam(String name) {
    final m = RegExp('$name=([^;:]*)').firstMatch(protocolInfo);
    return m?.group(1);
  }

  Duration? duration;
  final durationText = el.getAttribute('duration');
  if (durationText != null) {
    final parts = durationText.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = double.tryParse(parts[2]);
      if (h != null && m != null && s != null) {
        duration = Duration(
          hours: h,
          minutes: m,
          seconds: s.floor(),
          milliseconds: ((s - s.floor()) * 1000).round(),
        );
      }
    }
  }

  String? quality;
  final uri = Uri.tryParse(url);
  if (uri != null) quality = uri.queryParameters['quality'];

  return TitleRes(
    url: url,
    protocolInfo: protocolInfo,
    dtcpHost: protocolParam('DTCP1HOST'),
    dtcpPort: int.tryParse(protocolParam('DTCP1PORT') ?? ''),
    duration: duration,
    cleartextSize: int.tryParse(el.getAttribute('dlna:cleartextSize') ??
        el.getAttribute('cleartextSize') ??
        ''),
    quality: quality,
  );
}
