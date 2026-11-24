/// Dialog initial focus on the TV variant (plan 134).
///
/// A dialog that opens with nothing inside it asking for focus
/// leaves the D-pad focus on the screen behind the modal
/// barrier: the remote keeps operating the background, and the
/// dialog cannot even be cancelled (found on the real remote in
/// the Downloads candidate list). These tests drive the
/// credential screen's Downloads flow and the shared
/// confirmation dialog with key events only, the way a remote
/// control would, and pin that the standard variant keeps its
/// previous no-autofocus behaviour.
///
/// All credential values are the published known-answer dummies
/// from dtcp_kat.dart — never real credentials.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/credential_downloads.dart';
import 'package:tmhb/app/providers.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/core/core.dart';
import 'package:tmhb/ui/dtcp_credential_screen.dart';
import 'package:tmhb/ui/widgets.dart';

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

Widget _app(
  AppVariant variant,
  CredentialStore store,
  CredentialDownloadsScanner scanner,
) {
  return ProviderScope(
    overrides: [
      appVariantProvider.overrideWithValue(variant),
      credentialStoreProvider.overrideWithValue(store),
      credentialDownloadsScannerProvider.overrideWithValue(scanner),
    ],
    child: const MaterialApp(home: DtcpCredentialScreen()),
  );
}

CredentialDownloadsScanner _oneCandidateScanner() => CredentialDownloadsScanner(
  scanDownloads: () async => [
    DownloadsScannedFile(
      name: 'credentials.env',
      bytes: _envBytes(katSinkCert, katSinkPriv),
    ),
  ],
);

/// The candidate row inside the open chooser dialog.
Finder _candidateTile() => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byType(ListTile),
);

/// Whether the primary focus sits inside the widget [finder]
/// resolves to.
bool focusIsInside(Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final targets = finder.evaluate();
  if (targets.length != 1) return false;
  final target = targets.single;
  var inside = false;
  context.visitAncestorElements((element) {
    if (element == target) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

Future<void> _openChooser(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.tap(find.text('Downloads から探す'));
  await tester.pumpAndSettle();
  expect(find.text('資格情報ファイルが見つかりました'), findsOneWidget);
}

void main() {
  group('Downloads candidate dialogs on the TV variant', () {
    testWidgets('the first candidate holds focus as the list opens', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(AppVariant.tv, _store(), _oneCandidateScanner()),
      );
      await tester.pumpAndSettle();
      await _openChooser(tester);

      expect(focusIsInside(_candidateTile()), isTrue);
    });

    testWidgets('remote keys alone select, confirm and import', (tester) async {
      final store = _store();
      await tester.pumpWidget(
        _app(AppVariant.tv, store, _oneCandidateScanner()),
      );
      await tester.pumpAndSettle();
      await _openChooser(tester);

      // OK on the focused candidate opens the confirmation.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('資格情報を取り込む'), findsOneWidget);

      // The confirmation's focus is on 取り込む: OK imports.
      expect(focusIsInside(find.widgetWithText(TextButton, '取り込む')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await store.hasCredentials, isTrue);
    });

    testWidgets('remote keys alone can cancel the candidate list', (
      tester,
    ) async {
      final store = _store();
      await tester.pumpWidget(
        _app(AppVariant.tv, store, _oneCandidateScanner()),
      );
      await tester.pumpAndSettle();
      await _openChooser(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusIsInside(find.widgetWithText(TextButton, 'キャンセル')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('資格情報ファイルが見つかりました'), findsNothing);
      expect(find.text('資格情報を取り込む'), findsNothing);
      expect(await store.hasCredentials, isFalse);
    });
  });

  group('Downloads candidate dialogs on the standard variant', () {
    testWidgets('the list opens with no autofocus, as before', (tester) async {
      await tester.pumpWidget(
        _app(AppVariant.standard, _store(), _oneCandidateScanner()),
      );
      await tester.pumpAndSettle();
      await _openChooser(tester);

      expect(focusIsInside(_candidateTile()), isFalse);
    });
  });

  group('shared confirmation dialog', () {
    testWidgets('on TV, focus starts on cancel, not the action', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appVariantProvider.overrideWithValue(AppVariant.tv)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await confirmDialog(
                      context,
                      title: 'タイトルを削除',
                      message: '削除しますか？',
                    );
                  },
                  child: const Text('開く'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('タイトルを削除'), findsOneWidget);

      // OK as the dialog opens must hit cancel (the safe side),
      // never the destructive action.
      expect(focusIsInside(find.widgetWithText(TextButton, 'キャンセル')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
