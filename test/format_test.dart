/// Display formatting: quality mode labels (plan 16.4), area pref
/// labels and software version labels (plan 18).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/format.dart';

void main() {
  test('qualityModeLabel uses the official names for known modes', () {
    expect(qualityModeLabel(100), 'DR');
    expect(qualityModeLabel(101), '3倍');
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

  test('areaPrefLabel names the verified code (41 = Fukuoka)', () {
    expect(areaPrefLabel('41'), '福岡');
  });

  test('areaPrefLabel falls back to the raw value, never invents', () {
    // 40 is Fukuoka in the JIS table but unverified in Sony's own
    // numbering, so it must stay numeric (plan 18).
    expect(areaPrefLabel('40'), '40');
    expect(areaPrefLabel('13'), '13');
    expect(areaPrefLabel('0'), '0');
    expect(areaPrefLabel(''), '');
    expect(areaPrefLabel('abc'), 'abc');
  });
}
