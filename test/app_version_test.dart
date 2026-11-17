/// App version drift guard (plan 35): the version compiled into
/// the code (lib/core/app_version.dart) must match pubspec.yaml's
/// `version:` line. The settings screen shows the embedded
/// constants, so a release that bumps pubspec without the
/// constants (or the reverse) fails here instead of shipping a
/// screen that lies about the version again.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

void main() {
  test('embedded app version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(
      match,
      isNotNull,
      reason: 'pubspec.yaml has no parseable version: line',
    );
    expect(appVersionName, '${match![1]}.${match[2]}.${match[3]}');
    expect(appBuildNumber, int.parse(match[4]!));
  });
}
