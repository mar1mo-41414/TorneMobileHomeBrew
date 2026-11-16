/// EPG (programme guide) tests (plan 21): the ARIB STD-B24
/// decoder, the EPG / logo payload parsers, the acquisition
/// recipe at the service boundary, and the guide screen.
///
/// All fixtures are synthetic, built in this file: no broadcast
/// programme data is stored in the repository.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/state.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/epg_screen.dart';

// ---------------------------------------------------------------------------
// Synthetic EPG plaintext builder
// ---------------------------------------------------------------------------

const _channel = Channel(
  broadcastingType: 2,
  networkId: 0x1111,
  transportStreamId: 0x2222,
  serviceId: 0x3333,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト局',
);

/// B24 bytes of 「テレビ」 (LS3R + GR katakana), verified against
/// the reference decoder.
const _titleTv = [0x1b, 0x7c, 0xc6, 0xec, 0xd3];

/// B24 bytes of 「番組内容」 (GL kanji pairs).
const _labelContent = [0x48, 0x56, 0x41, 0x48, 0x46, 0x62, 0x4d, 0x46];

/// B24 bytes of 「番組」.
const _valueContent = [0x48, 0x56, 0x41, 0x48];

Uint8List _descriptor(int tag, List<int> body) =>
    Uint8List.fromList([tag, body.length, ...body]);

Uint8List _shortEvent(List<int> name, List<int> text) {
  return _descriptor(0x4d, [
    0x6a, 0x70, 0x6e, // 'jpn'
    name.length, ...name,
    text.length, ...text,
  ]);
}

Uint8List _extendedEvent(List<int> label, List<int> value) {
  final items = <int>[
    label.length, ...label,
    value.length, ...value,
  ];
  return _descriptor(0x4e, [
    0x00, // descriptor_number 0, last 0
    0x6a, 0x70, 0x6e,
    items.length, ...items,
    0, // text length
  ]);
}

Uint8List _event({
  required int id,
  required int mjd,
  required List<int> timeBcd,
  required List<int> durationBcd,
  List<int> descriptors = const [],
}) {
  final out = BytesBuilder();
  out.add([id >> 8, id & 0xff, mjd >> 8, mjd & 0xff]);
  out.add(timeBcd);
  out.add(durationBcd);
  out.add([descriptors.length >> 8, descriptors.length & 0xff]);
  out.add(descriptors);
  return out.toBytes();
}

Uint8List _block(List<int> eventsBytes) {
  final out = BytesBuilder();
  out.add([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]); // +0..6 filler
  out.add([0x33, 0x33]); // +7 serviceId
  out.add([0xe1]); // +9 flags
  out.add([0x00, 0x00]); // +10
  out.add([0x11, 0x11]); // +12 networkId
  out.add([0x22, 0x22]); // +14 transportStreamId
  out.add([0x00, 0x00]); // +16
  out.add(eventsBytes);
  return out.toBytes();
}

/// One service block with two events on 2026-11-16 (MJD 61360):
/// a titled 09:55-10:25 event and a no-information 10:25 event.
Uint8List syntheticPlaintext() {
  final ev1 = _event(
    id: 0x101,
    mjd: 61360,
    timeBcd: [0x09, 0x55, 0x00],
    durationBcd: [0x00, 0x30, 0x00],
    descriptors: [
      ..._shortEvent(_titleTv, const []),
      ..._extendedEvent(_labelContent, _valueContent),
      ..._descriptor(0x54, [0x70]),
    ],
  );
  final ev2 = _event(
    id: 0x102,
    mjd: 61360,
    timeBcd: [0x10, 0x25, 0x00],
    durationBcd: [0x00, 0x05, 0x00],
  );
  return _block([...ev1, ...ev2]);
}

/// Wraps a plaintext the way the device does: zlib, then XOR.
List<int> wrapEpgResponse(List<int> plain) {
  final zipped = ZLibEncoder().convert(plain);
  return zipped.map((b) => b ^ epgXorKey).toList();
}

// ---------------------------------------------------------------------------
// Synthetic logo file builder
// ---------------------------------------------------------------------------

Uint8List _logoRecord(int serviceId, List<int>? png) {
  final body = BytesBuilder();
  final total = 20 + (png?.length ?? 0);
  body.add([
    0, 0, total >> 8, total & 0xff, // decompressed length
    0, 0, 1, 0, 0, 0x2a, // variant / index bytes
    0, 0, 0, 0,
    serviceId >> 8, serviceId & 0xff,
    0, 0,
    (png?.length ?? 0) >> 8, (png?.length ?? 0) & 0xff,
  ]);
  if (png != null) body.add(png);
  return body.toBytes();
}

List<int> syntheticLogoFile() {
  final png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3];
  final out = BytesBuilder();
  out.add(ZLibEncoder().convert([7, 225, 10, 24, 11, 10, 28, 0])); // header
  out.add(ZLibEncoder().convert(_logoRecord(0x3333, png)));
  out.add(ZLibEncoder().convert(_logoRecord(0x4444, null)));
  return out.toBytes().map((b) => b ^ epgXorKey).toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ARIB STD-B24 decoder', () {
    test('GL kanji pairs', () {
      expect(decodeAribB24(_labelContent), '番組内容');
    });

    test('SS3 single-shifts to the katakana set for one character', () {
      expect(decodeAribB24([0x1d, 0x46]), 'テ');
    });

    test('LS3R invokes G3 (katakana) into GR', () {
      expect(decodeAribB24(_titleTv), 'テレビ');
    });

    test('additional symbols decode to the enclosed ideograph', () {
      expect(decodeAribB24([0x1b, 0x24, 0x3b, 0x7a, 0x56]), '🈑');
    });

    test('alnum is fullwidth at the standard size', () {
      expect(decodeAribB24([0x0e, 0x41, 0x31, 0x0f]), 'Ａ１');
    });

    test('GR defaults to the hiragana set', () {
      expect(decodeAribB24([0xa4]), 'い');
    });

    test('undecodable input degrades, never throws', () {
      expect(decodeAribB24([0x1b]), '');
      expect(decodeAribB24([0x21]), ''); // truncated pair: dropped
      expect(decodeAribB24([0x7e, 0x7e]), '□'); // unmapped cell
    });
  });

  group('broadcast text normalisation (EPG path)', () {
    test('enclosed ideograph marks become bracket labels', () {
      expect(normalizeBroadcastText('ニュース🈑'), 'ニュース[字]');
      expect(normalizeBroadcastText('番組🈟🈞'), '番組[新][再]');
    });
  });

  group('X-DTVToken over binary bodies', () {
    test('known values (SHA-1 over PIN + path + body[:256])', () {
      final body = [
        for (var i = 0; i < 256; i++) i,
        for (var i = 0; i < 44; i++) i,
      ];
      expect(
        TokenProvider.computeTokenBytes('58daf0', '/chEpg/EPGGet', body),
        'bMewukHcBeDzR98CFaWM5QaernU=',
      );
      expect(
        TokenProvider.computeTokenBytes('58daf0', '/chEpg/EPGGet', const []),
        'Xqt+rPF+cp7Umm93PIotmL7gZ4w=',
      );
    });
  });

  group('EPG plaintext parser', () {
    test('parses blocks, events, descriptors and JST times', () {
      final guide = parseEpgGuide(
        syntheticPlaintext(),
        const [_channel],
        broadcastingType: 2,
      );
      expect(guide.services, hasLength(1));
      final events = guide.services.single.events;
      expect(events, hasLength(2));

      final ev = events[0];
      expect(ev.eventId, 0x101);
      // 2026-11-16 09:55 JST = 00:55 UTC.
      expect(ev.start, DateTime.utc(2026, 11, 16, 0, 55));
      expect(ev.duration, const Duration(minutes: 30));
      expect(ev.title, 'テレビ');
      expect(ev.description, '番組');
      expect(ev.genreLevel1, 7);
      expect(ev.genreLevel2, 0);

      expect(events[1].title, isNull);
      expect(guide.eventCount, 2);
      expect(guide.from, DateTime.utc(2026, 11, 16, 0, 55));
    });

    test('response wrapping round-trips (XOR + zlib)', () {
      final plain = inflateEpgResponse(wrapEpgResponse(syntheticPlaintext()));
      expect(plain, syntheticPlaintext());
    });
  });

  group('channel logo parser', () {
    test('extracts PNGs by serviceId, skipping empty records', () {
      final logos = parseChannelLogos(syntheticLogoFile());
      expect(logos.keys, [0x3333]);
      expect(logos[0x3333]!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
    });
  });

  group('EPG acquisition recipe (service boundary)', () {
    test('verinfo x3 -> EPGGet -> parsed guide; logos parsed', () async {
      final versionTable = List<int>.generate(64, (i) => i * 3 & 0xff);
      late http.Request epgRequest;
      final client = MockClient((request) async {
        if (request.url.path == '/status/EPGVersionInfoGet') {
          return http.Response.bytes(versionTable, 200);
        }
        if (request.url.path == '/chEpg/EPGGet') {
          epgRequest = request;
          return http.Response.bytes(
              wrapEpgResponse(syntheticPlaintext()), 200);
        }
        if (request.url.path == '/chEpg/channelLogoDataGet') {
          return http.Response.bytes(syntheticLogoFile(), 200);
        }
        return http.Response('', 404);
      });
      final plain = WebApiTransport('192.0.2.1', client: client);
      final authed = WebApiTransport(
        '192.0.2.1',
        client: client,
        tokenProvider: const TokenProvider('58daf0'),
      );
      final service = WebApiEpgService(plain: plain, authed: authed);

      final guide = await service.getProgrammeGuide(2, const [_channel]);
      expect(guide.eventCount, 2);

      // The measured recipe: the version table repeated 3 times,
      // application/binary, token over the raw body.
      expect(epgRequest.method, 'POST');
      expect(epgRequest.headers['content-type'], 'application/binary');
      expect(epgRequest.bodyBytes, [
        ...versionTable,
        ...versionTable,
        ...versionTable,
      ]);
      expect(
        epgRequest.headers['x-dtvtoken'],
        TokenProvider.computeTokenBytes(
            '58daf0', '/chEpg/EPGGet', epgRequest.bodyBytes),
      );

      final logos = await service.getChannelLogos(2);
      expect(logos.keys, [0x3333]);
    });
  });

  group('programme guide screen', () {
    testWidgets('renders the channel column and event titles',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const reg = RegisteredNasne(
        host: '192.0.2.1',
        udn: 'uuid:test',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );
      final now = DateTime.now().toUtc();
      final guide = EpgGuide(
        broadcastingType: 2,
        services: [
          EpgServiceGuide(
            channel: _channel,
            events: [
              EpgEvent(
                eventId: 1,
                start: now,
                duration: const Duration(minutes: 30),
                title: 'テスト番組',
                description: '説明テキスト',
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            registrationStoreProvider.overrideWithValue(
                InMemoryRegistrationStore(const [reg])),
            epgGuideProvider.overrideWith((ref, r) async => guide),
            channelLogosProvider
                .overrideWith((ref, r) async => const <int, List<int>>{}),
          ],
          child: const MaterialApp(home: EpgScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('テスト局'), findsOneWidget);
      expect(find.text('テスト番組'), findsOneWidget);
      expect(find.textContaining('今日'), findsOneWidget);
    });
  });
}
