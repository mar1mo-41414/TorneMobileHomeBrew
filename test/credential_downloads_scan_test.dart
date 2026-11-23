/// Downloads scan flow on the credential import screen
/// (plan 127): only files whose pair passes the credential
/// store's validation are listed (by name only), and a listed
/// file reaches the vault only after its own confirmation.
///
/// All values are the published known-answer dummies from
/// dtcp_kat.dart (test authority pair) — never real credentials.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/credential_downloads.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/dtcp_credential_screen.dart';

import 'dtcp_kat.dart';

InMemoryCredentialStore _store() =>
    InMemoryCredentialStore(authorityKeys: [hexToBytes(katAuthPub)]);

Uint8List _envBytes(String certificate, String privateKey) =>
    Uint8List.fromList(
      utf8.encode(
        'PYDTCPIP_CERTIFICATE=$certificate\n'
        'PYDTCPIP_PRIVATE_KEY=$privateKey\n',
      ),
    );

CredentialDownloadsScanner _scanner(List<DownloadsScannedFile> files) =>
    CredentialDownloadsScanner(scanDownloads: () async => files);

Widget _app(CredentialStore store, CredentialDownloadsScanner scanner) {
  return ProviderScope(
    overrides: [
      credentialStoreProvider.overrideWithValue(store),
      credentialDownloadsScannerProvider.overrideWithValue(scanner),
    ],
    child: const MaterialApp(home: DtcpCredentialScreen()),
  );
}

void main() {
  group('DtcpCredentialScreen downloads scan', () {
    testWidgets('lists only validated files, by name only', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final scanner = _scanner([
        DownloadsScannedFile(
          name: 'credentials.env',
          bytes: _envBytes(katSinkCert, katSinkPriv),
        ),
        DownloadsScannedFile(
          name: 'credentials-bad.env',
          bytes: Uint8List.fromList(utf8.encode('not a credentials file')),
        ),
        DownloadsScannedFile(
          name: 'credentials-mismatch.env',
          bytes: _envBytes(katSinkCert, katSrcPriv),
        ),
      ]);
      await tester.pumpWidget(_app(_store(), scanner));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloads から探す'));
      await tester.pumpAndSettle();

      expect(find.text('資格情報ファイルが見つかりました'), findsOneWidget);
      expect(find.text('credentials.env'), findsOneWidget);
      // Files that fail parsing or validation are never listed.
      expect(find.text('credentials-bad.env'), findsNothing);
      expect(find.text('credentials-mismatch.env'), findsNothing);
      // And no credential material is on the surface.
      expect(find.textContaining(katSinkPriv), findsNothing);
      expect(find.textContaining(katSinkCert), findsNothing);
    });

    testWidgets('no import without the per-file confirmation', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = _store();
      final scanner = _scanner([
        DownloadsScannedFile(
          name: 'credentials.env',
          bytes: _envBytes(katSinkCert, katSinkPriv),
        ),
      ]);
      await tester.pumpWidget(_app(store, scanner));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloads から探す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('credentials.env'));
      await tester.pumpAndSettle();

      // The confirmation is up; cancelling leaves the vault empty.
      expect(find.text('資格情報を取り込む'), findsOneWidget);
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(await store.hasCredentials, isFalse);
    });

    testWidgets('confirming imports through the vault save path', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final store = _store();
      final scanner = _scanner([
        DownloadsScannedFile(
          name: 'credentials.env',
          bytes: _envBytes(katSinkCert, katSinkPriv),
        ),
      ]);
      await tester.pumpWidget(_app(store, scanner));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloads から探す'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('credentials.env'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取り込む'));
      await tester.pumpAndSettle();

      expect(await store.hasCredentials, isTrue);
      final loaded = await store.load();
      expect(bytesToHex(loaded!.certificate), katSinkCert);
      expect(bytesToHex(loaded.privateKey), katSinkPriv);
      expect(find.text('資格情報を保存しました'), findsOneWidget);
    });

    testWidgets('reports plainly when nothing importable is found', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final scanner = _scanner([
        DownloadsScannedFile(
          name: 'credentials-bad.env',
          bytes: Uint8List.fromList(utf8.encode('junk')),
        ),
      ]);
      await tester.pumpWidget(_app(_store(), scanner));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloads から探す'));
      await tester.pumpAndSettle();

      expect(find.textContaining('取り込める資格情報ファイルが'), findsOneWidget);
      expect(find.text('資格情報ファイルが見つかりました'), findsNothing);
    });

    testWidgets('one file seen from two folders is listed once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final bytes = _envBytes(katSinkCert, katSinkPriv);
      // The platform scans both Downloads spellings (plan 132);
      // a file reachable from both arrives as two sightings of
      // one path and must be offered once.
      final scanner = _scanner([
        DownloadsScannedFile(
          name: 'credentials.env',
          path: '/storage/emulated/0/Downloads/credentials.env',
          bytes: bytes,
        ),
        DownloadsScannedFile(
          name: 'credentials.env',
          path: '/storage/emulated/0/Downloads/credentials.env',
          bytes: bytes,
        ),
      ]);
      await tester.pumpWidget(_app(_store(), scanner));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Downloads から探す'));
      await tester.pumpAndSettle();

      expect(find.text('資格情報ファイルが見つかりました'), findsOneWidget);
      expect(find.text('credentials.env'), findsOneWidget);
    });
  });

  group('CredentialDownloadsScanner path dedupe (plan 132)', () {
    test('two sightings of one path collapse to a single file', () async {
      final bytes = _envBytes(katSinkCert, katSinkPriv);
      final files = await _scanner([
        DownloadsScannedFile(
          name: 'credentials.env',
          path: '/storage/emulated/0/Downloads/credentials.env',
          bytes: bytes,
        ),
        DownloadsScannedFile(
          name: 'credentials.env',
          path: '/storage/emulated/0/Downloads/credentials.env',
          bytes: bytes,
        ),
      ]).scan();
      expect(files, hasLength(1));
    });

    test('the same name at different paths stays two files', () async {
      final bytes = _envBytes(katSinkCert, katSinkPriv);
      final files = await _scanner([
        DownloadsScannedFile(
          name: 'credentials.env',
          path: '/storage/emulated/0/Download/credentials.env',
          bytes: bytes,
        ),
        DownloadsScannedFile(
          name: 'credentials.env',
          path: '/storage/emulated/0/Downloads/credentials.env',
          bytes: bytes,
        ),
      ]).scan();
      expect(files, hasLength(2));
    });

    test('files without a path always pass through', () async {
      final bytes = _envBytes(katSinkCert, katSinkPriv);
      final files = await _scanner([
        DownloadsScannedFile(name: 'credentials.env', bytes: bytes),
        DownloadsScannedFile(name: 'credentials.env', bytes: bytes),
      ]).scan();
      expect(files, hasLength(2));
    });
  });
}
