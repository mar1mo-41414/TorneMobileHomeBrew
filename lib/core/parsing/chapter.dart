/// Chapter positions from X_GetTitleInfo (plan 110 / 112).
///
/// The X_PvrControl action `X_GetTitleInfo` answers an xsrs
/// document whose root carries the fields directly — no
/// `item` wrapper: `chapterNum`, `chapterTime` and
/// `startPTS`. `chapterTime` is an underscore-separated
/// list of integers in units of 1/45000 s from the start
/// of the recording: the unit's silence-cut chapter
/// points, not an even grid. Plan 110 measured them
/// against the chapter points of the `.ifo` document the
/// DIDL `av:chapterInfo` URL serves and they agreed to
/// the millisecond on every sampled title.
///
/// The data is not trustworthy as served: short PR spots
/// carry a sentinel `startPTS` (the same value on every
/// one of them, far above the 33-bit PTS range) and
/// chapter tokens running far past the recording (plan
/// 110). [chapterPositionsFromTitleInfo] therefore
/// validates before it converts, and every failure means
/// "no chapters" — never an exception playback has to
/// survive.
library;

import 'package:xml/xml.dart';

import '../errors.dart';
import '../transport/xml_util.dart';

/// The unit `chapterTime` counts in: 1/45000 s per unit
/// (plan 110, settled against the `.ifo` second values
/// and the all-title census).
const int chapterTimeUnitsPerSecond = 45000;

/// The fields of an X_GetTitleInfo `Result` document.
class TitleInfoFields {
  const TitleInfoFields({this.chapterNum, this.chapterTime, this.startPTS});

  final String? chapterNum;
  final String? chapterTime;
  final String? startPTS;
}

/// Parses the xsrs document an X_GetTitleInfo call
/// returns (its `Result` string) into its fields. Throws
/// a [NasneError] of category parse when the document is
/// not the expected xsrs document.
TitleInfoFields parseTitleInfoDocument(String xmlText, String source) {
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
  return TitleInfoFields(
    chapterNum: childText(root, 'chapterNum'),
    chapterTime: childText(root, 'chapterTime'),
    startPTS: childText(root, 'startPTS'),
  );
}

/// Validates the fields of an X_GetTitleInfo document
/// and converts them to chapter positions, or returns an
/// empty list when the title has no usable chapters.
///
/// Validation (plan 110, from the all-title census and
/// the broken PR-spot data):
/// - `startPTS` parses and is below 2^33 (a 90 kHz PTS
///   is a 33-bit value; the broken spots carry a
///   sentinel far above it).
/// - `chapterTime`'s token count equals `chapterNum`.
/// - Every token parses as a non-negative integer and
///   the sequence is non-decreasing (the census found
///   every healthy title non-decreasing; a decrease is
///   corruption, an equal neighbour is a duplicate cut
///   the thinning below absorbs).
/// - The last token ends within the recording:
///   last <= durationSeconds * 45000 * 1.02.
///
/// Conversion thins points closer than a second to the
/// previous kept point (the census has real points a
/// few milliseconds after the start point, which as
/// skip targets would be indistinguishable from it),
/// and a list that keeps fewer than two points is no
/// chapter list at all.
List<Duration> chapterPositionsFromTitleInfo(
  TitleInfoFields fields, {
  required int durationSeconds,
}) {
  if (durationSeconds <= 0) return const [];
  final startPTS = int.tryParse(fields.startPTS?.trim() ?? '');
  if (startPTS == null || startPTS < 0 || startPTS >= 8589934592) {
    return const [];
  }
  final chapterNum = int.tryParse(fields.chapterNum?.trim() ?? '');
  final chapterTime = fields.chapterTime?.trim() ?? '';
  if (chapterNum == null || chapterNum < 0 || chapterTime.isEmpty) {
    return const [];
  }
  final tokens = <int>[];
  for (final part in chapterTime.split('_')) {
    final value = int.tryParse(part.trim());
    if (value == null || value < 0) return const [];
    tokens.add(value);
  }
  if (tokens.length != chapterNum || tokens.isEmpty) return const [];
  for (var i = 1; i < tokens.length; i++) {
    if (tokens[i] < tokens[i - 1]) return const [];
  }
  // The last point must land within the recording. The
  // coarse bound runs first so the precise one cannot
  // overflow on a garbage-but-parseable token.
  final durationUnits = durationSeconds * chapterTimeUnitsPerSecond;
  if (tokens.last > durationUnits * 2) return const [];
  if (tokens.last * 100 > durationUnits * 102) return const [];
  final positions = <Duration>[];
  for (final token in tokens) {
    final position = Duration(
      microseconds: token * 1000000 ~/ chapterTimeUnitsPerSecond,
    );
    if (positions.isNotEmpty &&
        position - positions.last < const Duration(seconds: 1)) {
      continue;
    }
    positions.add(position);
  }
  if (positions.length < 2) return const [];
  return positions;
}
