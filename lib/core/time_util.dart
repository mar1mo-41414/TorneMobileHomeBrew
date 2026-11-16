/// Date/time helpers for the xsrs notations (plan 12.5).
///
/// The device is asymmetric: it accepts `+09:00` (colon form) on input
/// and returns `+0900` (compact form). The asymmetry is absorbed here,
/// in the transport-adjacent layer, so models only hold [DateTime].
library;

/// Parses an xsrs / WebAPI timestamp in either offset notation
/// (`+0900` or `+09:00`), returning null when unparseable.
DateTime? parseNasneDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  var s = value.trim();
  // Normalise a trailing compact offset +0900 to the colon form +09:00.
  final m = RegExp(r'([+-]\d{2})(\d{2})$').firstMatch(s);
  if (m != null && !s.endsWith('Z')) {
    s = '${s.substring(0, m.start)}${m.group(1)}:${m.group(2)}';
  }
  return DateTime.tryParse(s);
}

/// Formats [value] the way the device expects on input:
/// `2026-11-18T04:00:00+09:00` (colon offset form, plan 11.7).
String formatNasneDateTime(DateTime value) {
  String two(int v) => v.toString().padLeft(2, '0');
  final local = value.toLocal();
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final base = '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}';
  return '$base$sign${two(abs.inHours)}:${two(abs.inMinutes % 60)}';
}
