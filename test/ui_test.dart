/// Widget tests for the v1 screens (plan 5.6), driven entirely by
/// fake implementations of the domain interfaces — the same swap the
/// composition root allows in production (plan 5.0 / 12.7). No
/// network or device is involved.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/main.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

const testReg = RegisteredNasne(
  host: '192.0.2.10',
  udn: 'uuid:test',
  friendlyName: 'nasne',
  macAddr: '00:11:22:33:44:55',
);

const testChannel = Channel(
  broadcastingType: 2,
  networkId: 30848,
  transportStreamId: 1,
  serviceId: 56832,
  serviceType: 1,
  channelNumber: 1,
  serviceName: 'テスト放送',
);

RecordSchedule sampleSchedule({
  String id = '101',
  int priorityFlag = 0,
  int durationSeconds = 1800,
}) {
  return RecordSchedule(
    id: id,
    start: DateTime.parse('2026-11-20T04:00:00+09:00'),
    durationSeconds: durationSeconds,
    conditionId: '1',
    channel: const ScheduleChannel(
      broadcastingType: 2,
      channelType: 2,
      serviceId: 56832,
    ),
    desiredQualityMode: 100,
    desiredMatchingId: '0x7880,0x7880,0xDE00,0x0000',
    reservationCreatorId: '2000',
    priorityFlag: priorityFlag,
    recordDestinationId: 'HDD',
    title: '既存の予約番組',
  );
}

class FakeDeviceInfo implements DeviceInfoService {
  @override
  Future<DeviceInfo> getDeviceInfo() async => const DeviceInfo(
        name: 'テストnasne',
        softwareVersion: '0260',
        currDate: '2026-11-16T15:00:00+09:00',
        pref: '東京都',
      );

  @override
  Future<List<HddEntry>> listHdds() async =>
      const [HddEntry(id: 0, internal: true, mounted: true, registered: true)];

  @override
  Future<HddInfo> getHddInfo(int id) async => const HddInfo(
        id: 0,
        internal: true,
        format: 'xfs',
        name: '内蔵HDD',
        usedBytes: 300000000000,
        freeBytes: 200000000000,
        totalBytes: 500000000000,
      );

  @override
  Future<NetworkInfo> getNetworkInfo() async => const NetworkInfo(
        macAddr: '00:11:22:33:44:55',
        ipv4Addr: '192.0.2.10',
        gateway: '192.0.2.1',
        dhcpEnabled: true,
      );

  @override
  Future<BcasInfo> getBcasInfo() async =>
      const BcasInfo(cardId: '0000123456789999', status: 'OK');

  @override
  Future<List<Channel>> listChannels(int broadcastingType) async =>
      const [testChannel];

  @override
  Future<LiveStatus> getLiveStatus() async =>
      const LiveStatus(sections: {}, raw: {});

  @override
  Future<List<RecNgItem>> listRecNg() async => const [];

  @override
  Future<ClientInfo> getClientInfo() async => const ClientInfo();
}

class FakeSchedules implements ScheduleService {
  FakeSchedules([List<RecordSchedule>? initial])
      : items = [...initial ?? [sampleSchedule()]];

  final List<RecordSchedule> items;
  List<RecordSchedule> conflictsToReturn = const [];
  ScheduleUpdate? lastUpdate;
  NewRecordSchedule? lastCreated;
  int _nextId = 200;

  @override
  Future<List<RecordSchedule>> listSchedules({
    int startingIndex = 0,
    int requestedCount = 50,
  }) async =>
      [...items];

  @override
  Future<String> createSchedule(NewRecordSchedule schedule) async {
    lastCreated = schedule;
    final id = '${_nextId++}';
    items.add(
      RecordSchedule(
        id: id,
        start: schedule.start,
        durationSeconds: schedule.durationSeconds,
        conditionId: '1',
        channel: schedule.channel,
        desiredQualityMode: schedule.desiredQualityMode,
        desiredMatchingId: schedule.desiredMatchingId,
        reservationCreatorId: schedule.reservationCreatorId,
        priorityFlag: schedule.priorityFlag,
        recordDestinationId: schedule.recordDestinationId,
      ),
    );
    return id;
  }

  @override
  Future<void> updateSchedule(ScheduleUpdate update) async {
    lastUpdate = update;
    final i = items.indexWhere((s) => s.id == update.id);
    if (i < 0) return;
    final old = items[i];
    items[i] = RecordSchedule(
      id: old.id,
      start: old.start,
      durationSeconds: old.durationSeconds,
      conditionId: update.conditionId ?? old.conditionId,
      channel: old.channel,
      desiredQualityMode: update.desiredQualityMode ?? old.desiredQualityMode,
      desiredMatchingId: old.desiredMatchingId,
      reservationCreatorId: old.reservationCreatorId,
      priorityFlag: update.priorityFlag,
      recordDestinationId: update.recordDestinationId ?? old.recordDestinationId,
      title: old.title,
    );
  }

  @override
  Future<void> deleteSchedule(String id) async {
    items.removeWhere((s) => s.id == id);
  }

  @override
  Future<List<RecordSchedule>> checkConflicts(
    NewRecordSchedule candidate,
  ) async =>
      conflictsToReturn;
}

class FakeTitles implements TitleCatalogService {
  @override
  Future<List<RecordedTitle>> listTitles({bool withMetadata = true}) async => [
        RecordedTitle(
          id: '201',
          title: '録画タイトルA',
          scheduledStart: DateTime.parse('2026-11-15T11:34:46+09:00'),
          scheduledDurationSeconds: 1800,
          channelName: 'テスト放送',
          copyCountRemaining: 10,
          protectFlag: true,
          description: '番組Aの概要',
          res: const [
            TitleRes(
              url: 'http://192.0.2.10:58890/web/video/pvr?id=201&quality=dr',
              protocolInfo: 'http-get:*:application/x-dtcp1:*',
              cleartextSize: 100000000,
              quality: 'dr',
            ),
          ],
        ),
        RecordedTitle(
          id: '202',
          title: '録画タイトルB',
          scheduledStart: DateTime.parse('2026-11-15T12:00:00+09:00'),
          scheduledDurationSeconds: 3600,
          channelName: 'テスト放送',
          copyCountRemaining: 3,
          newFlag: true,
        ),
      ];

  @override
  Future<int> countTitles() async => 2;

  @override
  Future<int> maxTitles() async => 3000;
}

class FakeSettings implements SettingsService {
  @override
  Future<String> getBoxName() async => 'テストnasne';

  @override
  Future<int> getMobileBitrate() async => 0;

  @override
  Future<void> setBoxName(String name) async {}

  @override
  Future<void> setMobileBitrate(int bitrateInfo) async {}
}

class FakeMetadata implements MetadataService {
  @override
  Future<DidlDocument> browse(String objectId) async =>
      const DidlDocument(containers: [], items: []);

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

class FakeDiscovery implements DiscoveryService {
  @override
  Future<List<NasneDevice>> discover({Duration? timeout}) async =>
      [NasneDevice.direct('192.0.2.20')];

  @override
  Future<NasneDevice> describe(Uri location) async =>
      NasneDevice.direct(location.host);
}

class FakeRegistration implements RegistrationService {
  @override
  Future<RegisteredNasne> register(NasneDevice device) async =>
      RegisteredNasne(
        host: device.host,
        udn: 'uuid:new',
        friendlyName: 'nasne',
        macAddr: '00:11:22:33:44:55',
      );

  @override
  Future<bool> verify(RegisteredNasne registration) async => true;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

class Fixture {
  Fixture({List<RegisteredNasne>? registrations, FakeSchedules? schedules})
      : schedules = schedules ?? FakeSchedules(),
        store = InMemoryRegistrationStore(registrations ?? [testReg]);

  final FakeSchedules schedules;
  final InMemoryRegistrationStore store;

  Widget app() {
    final bundle = DeviceServices(
      deviceInfo: FakeDeviceInfo(),
      settings: FakeSettings(),
      schedules: schedules,
      titles: FakeTitles(),
      metadata: FakeMetadata(),
      playback: const UnsupportedPlaybackEngine(),
    );
    return ProviderScope(
      overrides: [
        registrationStoreProvider.overrideWithValue(store),
        deviceServicesProvider.overrideWith((ref, reg) => bundle),
        discoveryServiceProvider.overrideWithValue(FakeDiscovery()),
        registrationServiceProvider.overrideWithValue(FakeRegistration()),
      ],
      child: const TmhbApp(),
    );
  }
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void useTabletSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1180, 820);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Pumps a few frames without waiting on snackbar timers.
Future<void> pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

void main() {
  testWidgets('home shows device summary, HDD usage and no messages',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(Fixture().app());
    await tester.pumpAndSettle();

    expect(find.text('テストnasne'), findsOneWidget);
    expect(find.textContaining('空き'), findsOneWidget);
    expect(find.text('メッセージはありません'), findsOneWidget);
    expect(find.text('録画失敗はありません'), findsOneWidget);
  });

  testWidgets('schedules list shows the existing reservation',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(Fixture().app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();

    expect(find.textContaining('既存の予約番組'), findsOneWidget);
    expect(find.textContaining('テスト放送'), findsWidgets);
  });

  testWidgets('create flow adds a reservation', (tester) async {
    usePhoneSize(tester);
    final fixture = Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新規予約'));
    await tester.pumpAndSettle();

    expect(find.text('新規予約'), findsWidgets);
    await tester.tap(find.text('予約を作成'));
    await pumpFrames(tester);

    expect(fixture.schedules.items, hasLength(2));
    expect(fixture.schedules.lastCreated, isNotNull);
    // Back on the list, both reservations are shown.
    expect(find.byType(ListTile), findsNWidgets(2));
  });

  testWidgets('conflict warning can be accepted', (tester) async {
    usePhoneSize(tester);
    final fixture = Fixture();
    fixture.schedules.conflictsToReturn = [sampleSchedule(id: '101')];
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新規予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('予約を作成'));
    await pumpFrames(tester);

    expect(find.text('競合する予約があります'), findsOneWidget);
    expect(fixture.schedules.items, hasLength(1));

    await tester.tap(find.text('このまま作成'));
    await pumpFrames(tester);
    expect(fixture.schedules.items, hasLength(2));
  });

  testWidgets('delete flow removes the reservation', (tester) async {
    usePhoneSize(tester);
    final fixture = Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('既存の予約番組'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(find.text('予約を削除'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('削除'),
      ),
    );
    await pumpFrames(tester);

    expect(fixture.schedules.items, isEmpty);
    expect(find.text('予約はありません'), findsOneWidget);
  });

  testWidgets('edit flow sends a sparse update with priorityFlag',
      (tester) async {
    usePhoneSize(tester);
    final fixture = Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('既存の予約番組'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編集'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('優先フラグ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新する'));
    await pumpFrames(tester);

    expect(fixture.schedules.lastUpdate, isNotNull);
    expect(fixture.schedules.lastUpdate!.id, '101');
    expect(fixture.schedules.lastUpdate!.priorityFlag, 1);
    expect(fixture.schedules.lastUpdate!.hasChangeField, isTrue);
  });

  testWidgets('time change replaces the reservation (delete + create)',
      (tester) async {
    usePhoneSize(tester);
    final fixture = Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('既存の予約番組'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('時刻を変更'));
    await tester.pumpAndSettle();

    // Change the duration from 30 to 45 minutes.
    await tester.enterText(find.byType(TextField), '45');
    await tester.tap(find.text('予約を作成'));
    await pumpFrames(tester);

    expect(fixture.schedules.items, hasLength(1));
    expect(fixture.schedules.items.single.id, isNot('101'));
    expect(fixture.schedules.items.single.durationSeconds, 2700);
  });

  testWidgets('titles list shows copy counts; playback shows the notice',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(Fixture().app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('録画済み'));
    await tester.pumpAndSettle();

    expect(find.text('録画タイトルA'), findsOneWidget);
    expect(find.text('残り 10 回'), findsOneWidget);
    expect(find.textContaining('全 2 件'), findsOneWidget);

    await tester.tap(find.text('録画タイトルA'));
    await tester.pumpAndSettle();
    expect(find.text('番組Aの概要'), findsOneWidget);

    await tester.tap(find.text('再生'));
    await tester.pumpAndSettle();
    expect(find.text('再生は未実装です'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
  });

  testWidgets('settings discovery registers a found device',
      (tester) async {
    usePhoneSize(tester);
    final fixture = Fixture();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAN 内の nasne を探す'));
    await tester.pumpAndSettle();

    expect(find.text('192.0.2.20'), findsOneWidget);
    final foundTile = find.ancestor(
      of: find.text('192.0.2.20'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: foundTile, matching: find.text('登録')),
    );
    await pumpFrames(tester);

    expect(find.textContaining('192.0.2.20'), findsWidgets);
    final stored = await fixture.store.loadAll();
    expect(stored.map((r) => r.host), contains('192.0.2.20'));
  });

  testWidgets('wide layout uses a rail and a two-pane schedule detail',
      (tester) async {
    useTabletSize(tester);
    await tester.pumpWidget(Fixture().app());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('予約'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('既存の予約番組'));
    await tester.pumpAndSettle();

    // List and detail are both visible (no page push).
    expect(find.textContaining('既存の予約番組'), findsWidgets);
    expect(find.text('編集'), findsOneWidget);
    expect(find.text('時刻を変更'), findsOneWidget);
  });
}
