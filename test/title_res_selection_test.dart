/// Playback res selection tests (plan 33): RecordedTitle resolves
/// its original-quality and mobile resources from the DIDL res
/// list, and res quality values get their display labels.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/format.dart';

TitleRes res(String quality) => TitleRes(
  url: 'http://192.0.2.10:58890/web/video/pvr?id=1&quality=$quality',
  protocolInfo: 'http-get:*:application/x-dtcp1:*',
  quality: quality,
);

RecordedTitle titleWith(List<TitleRes> res) =>
    RecordedTitle(id: '1', title: 'タイトル', res: res);

void main() {
  group('RecordedTitle res selection', () {
    test('dr + mobile: original is dr, mobile is mobile', () {
      final title = titleWith([res('dr'), res('mobile')]);
      expect(title.originalRes?.quality, 'dr');
      expect(title.mobileRes?.quality, 'mobile');
    });

    test('x3 + mobile: original is x3', () {
      final title = titleWith([res('x3'), res('mobile')]);
      expect(title.originalRes?.quality, 'x3');
      expect(title.mobileRes?.quality, 'mobile');
    });

    test('mobile listed first: original is still the non-mobile res', () {
      final title = titleWith([res('mobile'), res('dr')]);
      expect(title.originalRes?.quality, 'dr');
      expect(title.mobileRes?.quality, 'mobile');
    });

    test('dr only: no mobile resource', () {
      final title = titleWith([res('dr')]);
      expect(title.originalRes?.quality, 'dr');
      expect(title.mobileRes, isNull);
    });

    test('no res: both are null', () {
      final title = titleWith(const []);
      expect(title.originalRes, isNull);
      expect(title.mobileRes, isNull);
    });

    test('mobile only: original falls back to the first res', () {
      final title = titleWith([res('mobile')]);
      expect(title.originalRes?.quality, 'mobile');
      expect(title.mobileRes?.quality, 'mobile');
    });
  });

  group('resQualityLabel', () {
    test('measured values get their labels', () {
      expect(resQualityLabel('dr'), 'DR');
      expect(resQualityLabel('x3'), '3倍');
      expect(resQualityLabel('mobile'), 'モバイル');
    });

    test('unknown values fall back to the raw string', () {
      expect(resQualityLabel('something'), 'something');
      expect(resQualityLabel(null), '元画質');
    });
  });
}
