/// Live viewing tests (plan 39): the LiveTuner DIDL fixtures
/// parse into bands and channels with their channel identity and
/// current programme, the catalog service walks the tree through
/// the MetadataService boundary, and the stub engine reports
/// live viewing as unsupported like recorded playback.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

String didlFixture(String name) =>
    File('test/fixtures/dlna/$name').readAsStringSync();

/// Serves the canned DIDL documents by container id.
class FakeBrowseMetadata implements MetadataService {
  FakeBrowseMetadata(this.documents);

  final Map<String, DidlDocument> documents;
  final List<String> browsed = [];

  @override
  Future<DidlDocument> browse(String objectId) async {
    browsed.add(objectId);
    final doc = documents[objectId];
    if (doc == null) {
      throw NasneError.parse('test:browse', cause: 'unknown $objectId');
    }
    return doc;
  }

  @override
  Future<EpgGuide> getProgrammeGuide(
    int broadcastingType,
    List<Channel> channels,
  ) async =>
      EpgGuide(broadcastingType: broadcastingType, services: const []);

  @override
  Future<Map<int, List<int>>> getChannelLogos(int broadcastingType) async =>
      const {};
}

void main() {
  group('LiveTuner DIDL parsing', () {
    test('the LiveTuner root holds the three measured bands', () {
      final doc = parseDidl(didlFixture('browse_0_video_LiveTuner.xml'), 'test');
      expect(doc.containers.map((c) => c.id), [
        '0/video/LiveTuner/DTTB',
        '0/video/LiveTuner/BS',
        '0/video/LiveTuner/CS',
      ]);
      expect(doc.containers.map((c) => c.title), [
        '地上デジタル',
        'ＢＳデジタル',
        '１１０度ＣＳ',
      ]);
      expect(doc.items, isEmpty);
    });

    test('a live item converts to a channel with identity and programme',
        () {
      final doc =
          parseDidl(didlFixture('browse_0_video_LiveTuner_DTTB.xml'), 'test');
      expect(doc.items.length, 2);

      final channel = liveChannelFromDidl(doc.items.first);
      expect(channel.bandId, '0/video/LiveTuner/DTTB');
      // The id's hex parameters are the channelListGet space.
      expect(channel.networkId, 0x7880);
      expect(channel.transportStreamId, 0x7880);
      expect(channel.serviceId, 0xde00);
      expect(channel.channelName, 'ＮＨＫ総合１・北九州');
      expect(channel.channelNr, 30310);
      expect(channel.programTitle, 'テスト番組タイトルL1');
      expect(channel.genre, 'ニュース／報道');
      expect(channel.description, 'テスト概要L1');
      expect(channel.longDescription, 'テスト番組内容L1\nテスト出演者L1');
      expect(
        channel.programStart,
        DateTime.parse('2026-11-17T14:05:00+09:00'),
      );
      expect(channel.programEnd, DateTime.parse('2026-11-17T14:50:00+09:00'));
      // No copy-count on live items (recordings carry one).
      expect(doc.items.first.copyCountRemaining, isNull);
      // The three measured qualities, DTCP endpoint included.
      expect(channel.res.map((r) => r.quality), ['dr', 'x3', 'mobile']);
      expect(channel.res.first.dtcpHost, '192.0.2.1');
      expect(channel.res.first.dtcpPort, 57343);
      expect(
        channel.res.first.url,
        'http://192.0.2.1:58890/web/video/ch?nid=7880&tsid=7880&svid=de00&quality=dr',
      );
      // Plan-33 selection is shared with recordings.
      expect(channel.originalRes?.quality, 'dr');
      expect(channel.mobileRes?.quality, 'mobile');
    });

    test('the second channel keeps its own service id', () {
      final doc =
          parseDidl(didlFixture('browse_0_video_LiveTuner_DTTB.xml'), 'test');
      final channel = liveChannelFromDidl(doc.items[1]);
      expect(channel.serviceId, 0xde01);
      expect(channel.channelName, 'ＮＨＫ総合２・北九州');
    });
  });

  group('DlnaLiveCatalogService', () {
    test('walks the band containers in order and converts items', () async {
      final root = parseDidl(didlFixture('browse_0_video_LiveTuner.xml'), 't');
      final dttb =
          parseDidl(didlFixture('browse_0_video_LiveTuner_DTTB.xml'), 't');
      const empty = DidlDocument(containers: [], items: []);
      final metadata = FakeBrowseMetadata({
        '0/video/LiveTuner': root,
        '0/video/LiveTuner/DTTB': dttb,
        '0/video/LiveTuner/BS': empty,
        '0/video/LiveTuner/CS': empty,
      });
      final service = DlnaLiveCatalogService(metadata: metadata);
      final bands = await service.listLiveChannels();

      expect(metadata.browsed, [
        '0/video/LiveTuner',
        '0/video/LiveTuner/DTTB',
        '0/video/LiveTuner/BS',
        '0/video/LiveTuner/CS',
      ]);
      expect(bands.map((b) => b.title), ['地上デジタル', 'ＢＳデジタル', '１１０度ＣＳ']);
      expect(bands[0].channels.length, 2);
      expect(bands[0].channels.first.serviceId, 0xde00);
      expect(bands[1].channels, isEmpty);
      expect(bands[2].channels, isEmpty);
    });
  });

  group('engines', () {
    test('the stub engine reports live viewing as unsupported', () async {
      const engine = UnsupportedPlaybackEngine();
      final channel = LiveChannel(
        id: '0/video/LiveTuner/DTTB/ch?nid=7880&tsid=7880&svid=de00',
        bandId: '0/video/LiveTuner/DTTB',
        programTitle: 'テスト番組タイトルL1',
        res: const [
          TitleRes(
            url:
                'http://192.0.2.1:58890/web/video/ch?nid=7880&tsid=7880&svid=de00&quality=dr',
            protocolInfo: 'http-get:*:application/x-dtcp1:*',
            quality: 'dr',
          ),
        ],
      );
      // The stub throws synchronously; wrap the call so the
      // error surfaces as a future error for the matcher.
      Future<void> attempt() async =>
          engine.startLivePlayback(channel, channel.res.first);
      await expectLater(
        attempt(),
        throwsA(
          isA<NasneError>().having(
            (e) => e.category,
            'category',
            NasneErrorCategory.unsupported,
          ),
        ),
      );
    });
  });
}
