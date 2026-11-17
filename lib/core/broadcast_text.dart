/// Normalisation of broadcast metadata text (plan 16.1).
///
/// The nasne firmware delivers the ARIB STD-B24 additional symbols
/// used as programme marks (字幕・手話・再放送 …) as Unicode Private
/// Use Area code points, following the PUA assignment of the ARIB
/// gaiji font mapping (AFS ARIB font map, based on ARIB STD-B24).
/// Neither iOS nor Android system fonts carry glyphs for those code
/// points, so titles render with missing-glyph boxes. The characters
/// are present in the payload — this is a display-stage problem, not
/// a decode/parse loss (measured, plan 16.1).
///
/// [normalizeBroadcastText] rewrites each known PUA mark to the
/// bracketed text form used by Japanese EPG software ([手], [字], …)
/// at the point where device-supplied text enters a model. PUA code
/// points outside the table are passed through unchanged: their
/// equivalents are not established, and inventing labels is against
/// the project rule (plan 5.0 principle 5).
library;

/// ARIB STD-B24 additional symbols, programme-mark group
/// (row 90, points 48–84), PUA code point -> replacement text.
///
/// Evidence: glyph images of the AFS ARIB font map (ARIB STD-B24
/// based), cross-checked against an independent recorder-firmware
/// conversion table (plan 16.1). Points 64/65/71 of the same group
/// map to regular Unicode (U+2B1B / U+2B24 / U+26BF), so the
/// firmware sends those directly and they need no entry here.
/// Point 83 was believed to behave the same (U+3299), but a
/// measured DIDL payload (plan 56) shows the firmware sending it
/// as PUA 0xE19B after all, so it is listed below with the regular
/// code point as its replacement — the form the EPG path produces
/// and system fonts carry.
const Map<int, String> aribProgrammeMarkReplacements = {
  0xE0F8: '[HV]', // 90/48 HV
  0xE0F9: '[SD]', // 90/49 SD
  0xE0FA: '[P]', // 90/50 P
  0xE0FB: '[W]', // 90/51 W
  0xE0FC: '[MV]', // 90/52 MV
  0xE0FD: '[手]', // 90/53 手 (sign language)
  0xE0FE: '[字]', // 90/54 字 (subtitles)
  0xE0FF: '[双]', // 90/55 双 (dual audio)
  0xE180: '[デ]', // 90/56 デ (digital)
  0xE181: '[S]', // 90/57 S
  0xE182: '[二]', // 90/58 二 (bilingual)
  0xE183: '[多]', // 90/59 多 (multiplex audio)
  0xE184: '[解]', // 90/60 解 (commentary)
  0xE185: '[SS]', // 90/61 SS (surround)
  0xE186: '[B]', // 90/62 B
  0xE187: '[N]', // 90/63 N
  0xE18A: '[天]', // 90/66 天 (weather)
  0xE18B: '[交]', // 90/67 交 (traffic)
  0xE18C: '[映]', // 90/68 映
  0xE18D: '[無]', // 90/69 無 (free of charge)
  0xE18E: '[料]', // 90/70 料 (paid)
  0xE190: '[前]', // 90/72 前 (first part)
  0xE191: '[後]', // 90/73 後 (second part)
  0xE192: '[再]', // 90/74 再 (rebroadcast)
  0xE193: '[新]', // 90/75 新 (new programme)
  0xE194: '[初]', // 90/76 初 (first run)
  0xE195: '[終]', // 90/77 終 (final episode)
  0xE196: '[生]', // 90/78 生 (live)
  0xE197: '[販]', // 90/79 販 (sold as package media)
  0xE198: '[声]', // 90/80 声
  0xE199: '[吹]', // 90/81 吹 (dubbed)
  0xE19A: '[PPV]', // 90/82 PPV
  0xE19B: '㊙', // 90/83 ㊙ (U+3299; sent as PUA, plan 56)
  0xE19C: '[ほか]', // 90/84 ほか
  // Outside the row-90 block: U+2049 ⁉, identified by a measured
  // DIDL↔EIT positional match (plan 56). The EPG path produces
  // U+2049 itself and fonts carry it, so it is its own replacement.
  0xE2F0: '⁉', // ⁉ (U+2049; plan 56)
};

/// The same programme-mark group as delivered by the ARIB STD-B24
/// decoder (plan 21): the EPG path decodes the marks to their
/// regular Unicode code points (enclosed ideographs), which the
/// system fonts likewise lack. They are rewritten to the same
/// bracketed forms as the PUA group above, so both paths render
/// identically. Points 64/65/71/83 map to ordinary symbols
/// (U+2B1B / U+2B24 / U+26BF / U+3299) that fonts do carry, and are
/// not listed here.
const Map<int, String> aribProgrammeMarkUnicodeReplacements = {
  0x1F14A: '[HV]', // 90/48 HV
  0x1F14C: '[SD]', // 90/49 SD
  0x1F13F: '[P]', // 90/50 P
  0x1F146: '[W]', // 90/51 W
  0x1F14B: '[MV]', // 90/52 MV
  0x1F210: '[手]', // 90/53 手 (sign language)
  0x1F211: '[字]', // 90/54 字 (subtitles)
  0x1F212: '[双]', // 90/55 双 (dual audio)
  0x1F213: '[デ]', // 90/56 デ (digital)
  0x1F142: '[S]', // 90/57 S
  0x1F214: '[二]', // 90/58 二 (bilingual)
  0x1F215: '[多]', // 90/59 多 (multiplex audio)
  0x1F216: '[解]', // 90/60 解 (commentary)
  0x1F14D: '[SS]', // 90/61 SS (surround)
  0x1F131: '[B]', // 90/62 B
  0x1F13D: '[N]', // 90/63 N
  0x1F217: '[天]', // 90/66 天 (weather)
  0x1F218: '[交]', // 90/67 交 (traffic)
  0x1F219: '[映]', // 90/68 映
  0x1F21A: '[無]', // 90/69 無 (free of charge)
  0x1F21B: '[料]', // 90/70 料 (paid)
  0x1F21C: '[前]', // 90/72 前 (first part)
  0x1F21D: '[後]', // 90/73 後 (second part)
  0x1F21E: '[再]', // 90/74 再 (rebroadcast)
  0x1F21F: '[新]', // 90/75 新 (new programme)
  0x1F220: '[初]', // 90/76 初 (first run)
  0x1F221: '[終]', // 90/77 終 (final episode)
  0x1F222: '[生]', // 90/78 生 (live)
  0x1F223: '[販]', // 90/79 販 (sold as package media)
  0x1F224: '[声]', // 90/80 声
  0x1F225: '[吹]', // 90/81 吹 (dubbed)
  0x1F14E: '[PPV]', // 90/82 PPV
  0x1F200: '[ほか]', // 90/84 ほか
};

bool _isPua(int rune) => rune >= 0xE000 && rune <= 0xF8FF;

/// Returns [input] with known ARIB programme-mark code points
/// replaced by their bracketed text forms. Both delivery forms are
/// handled: the firmware's PUA code points (JSON paths) and the
/// regular Unicode code points produced by the B24 decoder (EPG
/// path). Strings without any known mark are returned as-is.
String normalizeBroadcastText(String input) {
  var hasMark = false;
  for (final rune in input.runes) {
    if (_isPua(rune) ||
        aribProgrammeMarkUnicodeReplacements.containsKey(rune)) {
      hasMark = true;
      break;
    }
  }
  if (!hasMark) return input;
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final replacement = aribProgrammeMarkReplacements[rune] ??
        aribProgrammeMarkUnicodeReplacements[rune];
    if (replacement != null) {
      buffer.write(replacement);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Nullable variant for optional text fields.
String? normalizeBroadcastTextOrNull(String? input) =>
    input == null ? null : normalizeBroadcastText(input);
