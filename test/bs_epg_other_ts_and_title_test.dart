import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/core/core.dart';

const _bs = Channel(
  broadcastingType: 3,
  networkId: 4,
  transportStreamId: 17489,
  serviceId: 193,
  serviceType: 1,
  channelNumber: 193,
  serviceName: 'BS test',
);
const _terrestrial = Channel(
  broadcastingType: 2,
  networkId: 4,
  transportStreamId: 17489,
  serviceId: 193,
  serviceType: 1,
  channelNumber: 193,
  serviceName: 'Terrestrial test',
);

Uint8List eitSection(int tableId, {bool titled = true}) {
  const bytes = [0x1b, 0x7c, 0xc6, 0xec, 0xd3]; // テレビ
  final descriptor = titled
      ? [0x4d, 10, 0x6a, 0x70, 0x6e, 5, ...bytes, 0]
      : <int>[];
  final event = [
    0, 42, 0xef, 0xb0,
    0x09, 0x55, 0, 0, 0x30, 0,
    0xf0, descriptor.length,
    ...descriptor,
  ];
  final size = 11 + event.length + 4;
  final data = [
    tableId, 0xb0 | ((size >> 8) & 0x0f), size & 255,
    0, 193, 0xc1, 0, 0,
    0x44, 0x51, 0, 4, 0, tableId,
    ...event,
  ];
  final crc = crc32Mpeg(data);
  return Uint8List.fromList([...data, (crc >> 24) & 255,
    (crc >> 16) & 255, (crc >> 8) & 255, crc & 255]);
}

void main() {
  test('BS EIT other-TS 0x60 yields an actual title', () {
    final guide = parseEpgGuide(eitSection(0x60), const [_bs], broadcastingType: 3);
    expect(guide.services.single.events.single.title, 'テレビ');
  });

  test('BS EIT other-TS 0x68 yields an actual title', () {
    final guide = parseEpgGuide(eitSection(0x68), const [_bs], broadcastingType: 3);
    expect(guide.services.single.events.single.title, 'テレビ');
  });

  test('Terrestrial EPG excludes other-TS EIT in this patch', () {
    final guide = parseEpgGuide(eitSection(0x60), const [_terrestrial], broadcastingType: 2);
    expect(guide.services, isEmpty);
  });

  test('Corrupted CRC EIT is ignored', () {
    final raw = eitSection(0x60);
    raw[raw.length - 1] ^= 0xff;
    expect(parseEpgGuide(raw, const [_bs], broadcastingType: 3).services, isEmpty);
  });

  test('BS extended 番組名 fills missing title preserving details', () {
    final event = EpgEvent(
      eventId: 1,
      start: DateTime.utc(2026, 11, 18, 1),
      duration: const Duration(minutes: 90),
      description: 'metadata',
      extendedItems: const [EpgExtendedItem(label: '番組名', value: '映画タイトル')],
    );
    final fixed = bsTitleFromExtended(event);
    expect(fixed.title, '映画タイトル');
    expect(fixed.description, 'metadata');
    expect(fixed.extendedItems, hasLength(1));
  });

  test('Do not override an existing short title', () {
    final event = EpgEvent(
      eventId: 1,
      start: DateTime.utc(2026, 11, 18, 1),
      duration: const Duration(minutes: 90),
      title: 'original',
      extendedItems: const [EpgExtendedItem(label: '番組名', value: 'different')],
    );
    expect(bsTitleFromExtended(event).title, 'original');
  });
}
