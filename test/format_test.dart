/// Display formatting: quality mode labels (plan 16.4), area labels
/// (plan 18, expanded in plan 19) and software version labels
/// (plan 18).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/format.dart';

void main() {
  test('qualityModeLabel uses the official names for known modes', () {
    // XSRS value space (plan 28): 100 = DR, 230 = 3倍, from
    // torne-created items. 101 belongs to the WebAPI JSON space
    // and is not labelled here.
    expect(qualityModeLabel(100), 'DR');
    expect(qualityModeLabel(230), '3倍');
    expect(qualityModeLabel(101), '101');
  });

  test('qualityModeLabel falls back to the raw number, never invents', () {
    expect(qualityModeLabel(102), '102');
    expect(qualityModeLabel(0), '0');
    expect(qualityModeLabel(-1), '-1');
  });

  test('softwareVersionLabel re-dots the raw 4-digit version', () {
    expect(softwareVersionLabel('0260'), '2.60');
    expect(softwareVersionLabel('1000'), '10.00');
    expect(softwareVersionLabel('0205'), '2.05');
  });

  test('softwareVersionLabel falls back to the raw value', () {
    expect(softwareVersionLabel('2.60'), '2.60');
    expect(softwareVersionLabel('260'), '260');
    expect(softwareVersionLabel(''), '');
    expect(softwareVersionLabel('abcd'), 'abcd');
  });

  test('areaLabel resolves the verified anchor pair (55, 41)', () {
    // The owner's unit (Fukuoka) returns areaIdentifierCode 55,
    // pref 41 (plan 19).
    expect(areaLabel('55', '41'), '福岡');
  });

  test('areaLabel resolves pairs across the official table', () {
    // (areaIdentifierCode, pref) pairs from the table built into
    // the unit's own Web UI (plan 19).
    expect(areaLabel('10', '2'), '北海道（札幌）');
    expect(areaLabel('13', '1'), '北海道（帯広）');
    expect(areaLabel('22', '3'), '青森');
    expect(areaLabel('23', '14'), '東京');
    expect(areaLabel('41', '27'), '京都');
    expect(areaLabel('40', '28'), '大阪');
    expect(areaLabel('62', '48'), '沖縄');
  });

  test('areaLabel disambiguates the split areas by the pair', () {
    // areaIdentifierCode 12, 23 and 58 each cover two areas; only
    // the (code, pref) pair tells them apart (plan 19).
    expect(areaLabel('12', '1'), '北海道（旭川）');
    expect(areaLabel('12', '2'), '北海道（旭川・空知）');
    expect(areaLabel('23', '49'), '東京（島部）');
    expect(areaLabel('58', '47'), '鹿児島');
    expect(areaLabel('58', '50'), '鹿児島（南西諸島）');
  });

  test('areaLabel falls back to a unique pref when the code is unusable', () {
    expect(areaLabel(null, '41'), '福岡');
    expect(areaLabel('', '27'), '京都');
    expect(areaLabel('99', '41'), '福岡');
    // Supersedes plan 18, where 40 had to stay numeric for lack of
    // evidence: in the official table pref 40 is 高知 (plan 19).
    expect(areaLabel(null, '40'), '高知');
  });

  test('areaLabel falls back to the raw value, never invents', () {
    // Hokkaido prefs 1 and 2 are ambiguous without the code.
    expect(areaLabel(null, '1'), '1');
    expect(areaLabel(null, '2'), '2');
    expect(areaLabel('99', '99'), '99');
    expect(areaLabel('0', '0'), '0');
    expect(areaLabel('abc', 'xyz'), 'xyz');
    expect(areaLabel(null, null), '');
  });
}
