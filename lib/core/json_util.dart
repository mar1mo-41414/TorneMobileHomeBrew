/// Small tolerant JSON helpers.
///
/// The nasne WebAPI returns numbers as JSON numbers in the measured
/// responses, but several fields historically flip between string and
/// number shapes across firmware variants; the parsers therefore accept
/// both and fail with a [NasneError] of category `parse` only when a
/// required value is absent or unparseable.
library;

import 'errors.dart';

Map<String, dynamic> asJsonMap(Object? value, String source) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw NasneError.parse(source, cause: 'expected a JSON object');
}

String? optString(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

String reqString(Map<String, dynamic> json, String key, String source) {
  final v = optString(json, key);
  if (v == null) throw NasneError.parse(source, cause: 'missing "$key"');
  return v;
}

int? optInt(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int reqInt(Map<String, dynamic> json, String key, String source) {
  final v = optInt(json, key);
  if (v == null) throw NasneError.parse(source, cause: 'missing "$key"');
  return v;
}

bool? optBool(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return null;
}

/// Flag fields in the WebAPI are 0/1 integers; treat them as booleans
/// with a default of false.
bool flag(Map<String, dynamic> json, String key) => optBool(json, key) ?? false;

List<dynamic> optList(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v == null) return const [];
  if (v is List) return v;
  return const [];
}
