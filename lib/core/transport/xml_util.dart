/// XML helpers shared by the SOAP / description / DIDL parsers.
library;

import 'package:xml/xml.dart';

/// Escapes a value for inclusion as XML element text.
String escapeXmlText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// Escapes a value for inclusion in a double-quoted XML attribute.
String escapeXmlAttribute(String value) {
  return escapeXmlText(value).replaceAll('"', '&quot;');
}

/// Direct child elements of [parent] with the given local name
/// (namespace-agnostic: the device mixes prefixed and default
/// namespaces across its services).
Iterable<XmlElement> childElements(XmlElement parent, String localName) {
  return parent.childElements.where((e) => e.name.local == localName);
}

/// First direct child element with the given local name, or null.
XmlElement? firstChild(XmlElement parent, String localName) {
  for (final e in parent.childElements) {
    if (e.name.local == localName) return e;
  }
  return null;
}

/// Text of the first direct child with the given local name, or null.
String? childText(XmlElement parent, String localName) {
  return firstChild(parent, localName)?.innerText;
}

/// All descendant elements with the given local name.
Iterable<XmlElement> descendants(XmlElement root, String localName) {
  return root.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == localName);
}

/// First descendant element with the given local name, or null.
XmlElement? firstDescendant(XmlElement root, String localName) {
  for (final e in root.descendants.whereType<XmlElement>()) {
    if (e.name.local == localName) return e;
  }
  return null;
}
