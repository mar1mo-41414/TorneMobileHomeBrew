/// DIDL parsing against the masked phase 0 fixtures.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/core/parsing/didl.dart';

String didlFixture(String name) =>
    File('test/fixtures/dlna/$name').readAsStringSync();

void main() {
  test('container listing: 0/video holds the 5 measured containers', () {
    final doc = parseDidl(didlFixture('browse_0_video.xml'), 'test');
    expect(doc.containers.map((c) => c.id), containsAll([
      '0/video/genre',
      '0/video/date',
      '0/video/all',
      '0/video/folder',
      '0/video/LiveTuner',
    ]));
    expect(doc.items, isEmpty);
  });

  test('all-recordings items carry res / COGCount / join keys', () {
    final doc = parseDidl(didlFixture('browse_0_video_all.xml'), 'test');
    expect(doc.items.length, 2);

    final first = doc.items.first;
    expect(first.titleId, '10000000000000000002');
    expect(first.copyCountRemaining, 10);
    expect(first.res.length, 3);
    final dr = first.res.firstWhere((r) => r.quality == 'dr' && r.url.endsWith('quality=dr'));
    expect(dr.dtcpHost, '192.0.2.1');
    expect(dr.dtcpPort, 57343);
    expect(dr.duration, const Duration(minutes: 14, seconds: 14));
    expect(dr.cleartextSize, 1564986240);
    expect(first.res.map((r) => r.quality), contains('mobile'));
    expect(first.channelName, isNotNull);
    expect(first.description, 'テスト概要テキスト');

    final second = doc.items[1];
    expect(second.titleId, '10000000000000000001');
    expect(second.copyCountRemaining, 9);
  });
}
