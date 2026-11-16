/// Display formatting: quality mode labels (plan 16.4).
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
}
