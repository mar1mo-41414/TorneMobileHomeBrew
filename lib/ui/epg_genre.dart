/// ARIB genre level-1 table for the programme guide
/// (plan 86, plan 85 item 10): the display name and the
/// tile colour of each content-descriptor genre nibble.
///
/// The EPG parser has carried genreLevel1 / genreLevel2
/// since plan 21, but the guide grid painted every tile in
/// the same surface colour, so a viewer could not tell a
/// drama from a news programme at a glance. The official
/// torne mobile colours its guide by genre (plan 85.4,
/// sourced).
///
/// This table is the single source for genre names: the
/// programme search's filter labels (plan 86 item 8, which
/// briefly kept its own copy) resolve through here too.
/// The reserved (12 / 13) and extension (14) ranges name
/// nothing a viewer would recognise, so they get neither a
/// label nor a colour.
library;

import 'package:material_ui/material_ui.dart';

/// The display name of an ARIB genre level-1 value, or
/// null when the value names nothing a viewer would
/// recognise (no genre, the reserved / extension ranges,
/// out-of-range values).
String? epgGenreLabel(int? genreLevel1) => switch (genreLevel1) {
  0 => 'ニュース・報道',
  1 => 'スポーツ',
  2 => '情報・ワイドショー',
  3 => 'ドラマ',
  4 => '音楽',
  5 => 'バラエティ',
  6 => '映画',
  7 => 'アニメ・特撮',
  8 => 'ドキュメンタリー・教養',
  9 => '劇場・公演',
  10 => '趣味・教育',
  11 => '福祉',
  15 => 'その他',
  _ => null,
};

/// The base colour of an ARIB genre level-1 value, or null
/// when the genre has no colour (see [epgGenreLabel]). The
/// hues are spread around the wheel so neighbouring tiles
/// read as different kinds at a glance; a tile never paints
/// this raw — it paints a blend over the theme surface
/// (see [epgGenreTileColor]), so text stays on a
/// surface-like background in both themes.
Color? epgGenreColor(int? genreLevel1) => switch (genreLevel1) {
  0 => const Color(0xFF3D7BD6), // ニュース・報道: blue
  1 => const Color(0xFF3E9B4F), // スポーツ: green
  2 => const Color(0xFF2AA198), // 情報・ワイドショー: teal
  3 => const Color(0xFFE75480), // ドラマ: pink
  4 => const Color(0xFF9B59B6), // 音楽: purple
  5 => const Color(0xFFF39C2C), // バラエティ: orange
  6 => const Color(0xFF5B5BD6), // 映画: indigo
  7 => const Color(0xFFE5484D), // アニメ・特撮: red
  8 => const Color(0xFFA97142), // ドキュメンタリー・教養: brown
  9 => const Color(0xFF607D8B), // 劇場・公演: blue grey
  10 => const Color(0xFFC0A030), // 趣味・教育: gold
  11 => const Color(0xFF7E57C2), // 福祉: deep purple
  15 => const Color(0xFF9E9E9E), // その他: grey
  _ => null,
};

/// How strongly a genre colour tints its tile: enough for
/// the kind to read at a glance, light enough that the
/// tile stays a text background.
const double epgGenreTintStrength = 0.30;

/// The background colour of a guide tile for
/// [genreLevel1]: the genre colour blended at
/// [epgGenreTintStrength] over [surface]. Genres without
/// a colour (and events without a genre) keep [fallback] —
/// the colour un-genred tiles have always had.
Color epgGenreTileColor({
  required int? genreLevel1,
  required Color surface,
  required Color fallback,
}) {
  final base = epgGenreColor(genreLevel1);
  if (base == null) return fallback;
  return Color.alphaBlend(
    base.withAlpha((epgGenreTintStrength * 255).round()),
    surface,
  );
}
