/// Broadcast text normalisation (plan 16.1): the firmware delivers
/// ARIB programme marks as PUA code points; they must enter models in
/// bracketed text form. Strings below are the shapes measured on the
/// real device (programme titles anonymised only in their unique
/// parts; the mark sequences are the measured ones).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('normalizeBroadcastText', () {
    test('converts the measured title suffixes', () {
      // 手話 programme: [字] then [手] (measured order).
      expect(
        normalizeBroadcastText('５分でみんなの手話（４）家族\uE0FE\uE0FD'),
        '５分でみんなの手話（４）家族[字][手]',
      );
      // Nature programme: [字].
      expect(
        normalizeBroadcastText('さわやか自然百景\u3000選\u3000大阪\u3000泉州のため池\uE0FE'),
        'さわやか自然百景\u3000選\u3000大阪\u3000泉州のため池[字]',
      );
      // Health programme (recNg): [解] then [字].
      expect(
        normalizeBroadcastText('きょうの健康\u3000ＣＯＰＤ新ガイドラインで対策\u3000注目！新たな治療の選択肢\uE184\uE0FE'),
        'きょうの健康\u3000ＣＯＰＤ新ガイドラインで対策\u3000注目！新たな治療の選択肢[解][字]',
      );
      // Sign-language news (recNg): [手].
      expect(
        normalizeBroadcastText('ＮＨＫ手話ニュース８４５\uE0FD'),
        'ＮＨＫ手話ニュース８４５[手]',
      );
    });

    test('covers the programme-mark group', () {
      const expected = {
        0xE0F8: '[HV]',
        0xE0F9: '[SD]',
        0xE0FA: '[P]',
        0xE0FB: '[W]',
        0xE0FC: '[MV]',
        0xE0FD: '[手]',
        0xE0FE: '[字]',
        0xE0FF: '[双]',
        0xE180: '[デ]',
        0xE181: '[S]',
        0xE182: '[二]',
        0xE183: '[多]',
        0xE184: '[解]',
        0xE185: '[SS]',
        0xE186: '[B]',
        0xE187: '[N]',
        0xE18A: '[天]',
        0xE18B: '[交]',
        0xE18C: '[映]',
        0xE18D: '[無]',
        0xE18E: '[料]',
        0xE190: '[前]',
        0xE191: '[後]',
        0xE192: '[再]',
        0xE193: '[新]',
        0xE194: '[初]',
        0xE195: '[終]',
        0xE196: '[生]',
        0xE197: '[販]',
        0xE198: '[声]',
        0xE199: '[吹]',
        0xE19A: '[PPV]',
        0xE19B: '㊙',
        0xE19C: '[ほか]',
        0xE2F0: '⁉',
      };
      expect(aribProgrammeMarkReplacements, expected);
      for (final entry in expected.entries) {
        expect(
          normalizeBroadcastText(String.fromCharCode(entry.key)),
          entry.value,
          reason: 'U+${entry.key.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('converts the plan-56 measured DIDL strings', () {
      // FBS live detail (2026-11-17): the firmware sent U+E2F0 for
      // ⁉ and U+E19B for ㊙; identified by positional match against
      // the same programme's EIT text decoded with the B24 decoder.
      expect(
        normalizeBroadcastText('オモウマい店\uE0FE【北海道】謎解き食堂の'
            'ギョウザが見当たらないギョウザ定食\uE2F0'),
        'オモウマい店[字]【北海道】謎解き食堂の'
            'ギョウザが見当たらないギョウザ定食⁉',
      );
      expect(
        normalizeBroadcastText('肉汁ジュワーッ\uE19Bギョウザ'),
        '肉汁ジュワーッ㊙ギョウザ',
      );
    });

    test('passes plain text and unknown PUA through unchanged', () {
      const plain = 'ニュース６４５福岡';
      expect(normalizeBroadcastText(plain), plain);
      // U+E123 is not an established mark: never invent a label.
      expect(normalizeBroadcastText('x\uE123y'), 'x\uE123y');
      expect(normalizeBroadcastText(''), '');
      expect(normalizeBroadcastTextOrNull(null), isNull);
    });
  });

  group('parse entry points normalise', () {
    test('xsrs recorded title', () {
      const doc = '<?xml version="1.0"?>'
          '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/">'
          '<item id="1"><title>番組\uE0FE\uE0FD</title></item></xsrs>';
      final items = parseXsrsItems(doc, 'test');
      final title = recordedTitleFromXsrs(items.single, source: 'test');
      expect(title.title, '番組[字][手]');
    });

    test('xsrs schedule title', () {
      const doc = '<?xml version="1.0"?>'
          '<xsrs xmlns="urn:schemas-xsrs-org:metadata-1-0/x_srs/">'
          '<item id="7"><title>予約\uE192</title>'
          '<scheduledStartDateTime>2026-11-18T04:00:00+0900</scheduledStartDateTime>'
          '<scheduledDuration>300</scheduledDuration>'
          '<scheduledChannelID broadcastingType="2" channelType="2">0xde00</scheduledChannelID>'
          '</item></xsrs>';
      final items = parseXsrsItems(doc, 'test');
      final schedule = recordScheduleFromXsrs(items.single, source: 'test');
      expect(schedule.title, '予約[再]');
    });

    test('DIDL title / description / longDescription / channelName', () {
      const doc = '<DIDL-Lite '
          'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" '
          'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
          'xmlns:arib="urn:schemas-arib-or-jp:elements-1-0/">'
          '<item id="i1" parentID="0/video/all">'
          '<dc:title>タイトル\uE193</dc:title>'
          '<dc:description>概要\uE0FE</dc:description>'
          '<arib:longDescription>詳細\uE195</arib:longDescription>'
          '<upnp:channelName>チャンネル\uE196</upnp:channelName>'
          '</item></DIDL-Lite>';
      final parsed = parseDidl(doc, 'test');
      final item = parsed.items.single;
      expect(item.title, 'タイトル[新]');
      expect(item.description, '概要[字]');
      expect(item.longDescription, '詳細[終]');
      expect(item.channelName, 'チャンネル[生]');
    });

    test('recNg item title', () {
      final item = RecNgItem.fromJson(const {
        'id': '1',
        'title': '健康\uE184\uE0FE',
      });
      expect(item.title, '健康[解][字]');
    });
  });
}
