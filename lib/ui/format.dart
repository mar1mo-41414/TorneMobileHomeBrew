/// Display formatting helpers for the UI layer.
///
/// The device lives in JST and every measured timestamp uses the
/// +0900 offset (plan 13.8), so the UI renders wall-clock times in
/// JST regardless of the host timezone, matching the core's send-side
/// convention (core/time_util.dart).
library;

String _two(int v) => v.toString().padLeft(2, '0');

/// The JST wall clock of [instant], as a UTC DateTime whose fields
/// hold the JST values. Read the fields only; do not pass this to
/// timezone-aware formatters.
DateTime jstWallClock(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 9));

/// Interprets [wall]'s fields as a JST wall time and returns the
/// corresponding instant.
DateTime instantFromJstWall(DateTime wall) => DateTime.utc(
  wall.year,
  wall.month,
  wall.day,
  wall.hour,
  wall.minute,
  wall.second,
).subtract(const Duration(hours: 9));

/// `2026/11/18`
String formatDateJst(DateTime instant) {
  final w = jstWallClock(instant);
  return '${w.year}/${_two(w.month)}/${_two(w.day)}';
}

/// `04:00`
String formatTimeJst(DateTime instant) {
  final w = jstWallClock(instant);
  return '${_two(w.hour)}:${_two(w.minute)}';
}

/// `2026/11/18 04:00`
String formatDateTimeJst(DateTime instant) =>
    '${formatDateJst(instant)} ${formatTimeJst(instant)}';

/// Japanese weekday label of the JST wall clock.
String formatWeekdayJst(DateTime instant) {
  const labels = ['月', '火', '水', '木', '金', '土', '日'];
  return labels[jstWallClock(instant).weekday - 1];
}

/// `2026/11/18 (水) 04:00`
String formatDateTimeWithWeekdayJst(DateTime instant) =>
    '${formatDateJst(instant)} (${formatWeekdayJst(instant)}) '
    '${formatTimeJst(instant)}';

/// Duration text: `30秒` / `45分` / `1時間` / `1時間30分`.
String formatDurationSeconds(int seconds) {
  if (seconds < 60) return '$seconds秒';
  final m = seconds ~/ 60;
  if (m < 60) return '$m分';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '$h時間' : '$h時間$rest分';
}

/// Human-readable byte size (binary units).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[i]}';
}

/// Official label of a recording quality mode (`desiredQualityMode`).
///
/// The nasne recording modes are named, not numbered, in the official
/// apps (plan 5.0 principle 5): 100 = DR, 101 = 3倍. Values whose
/// official label has not been confirmed fall back to the raw number;
/// labels are never invented (plan 16.4).
String qualityModeLabel(int mode) => switch (mode) {
      100 => 'DR',
      101 => '3倍',
      _ => '$mode',
    };

/// Masks an identifier for display, keeping only the last [keep]
/// characters (B-CAS card ids and similar, plan section 7).
String maskTail(String value, {int keep = 4}) {
  if (value.length <= keep) return '••';
  return '••${value.substring(value.length - keep)}';
}

/// Masks a MAC address: the last three octets are the PIN derivation
/// source (plan 11.5), so only the first three octets are shown.
String maskMac(String mac) {
  final parts = mac.split(':');
  if (parts.length == 6) {
    return '${parts[0]}:${parts[1]}:${parts[2]}:••:••:••';
  }
  return maskTail(mac);
}
