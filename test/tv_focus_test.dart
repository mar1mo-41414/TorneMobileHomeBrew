/// TV focus support (plan 123): the TV variant's text fields
/// must not open the software keyboard on focus, editing happens
/// in a dialog opened by an explicit OK, and display-only edge
/// items of a scroll view must hold focus so D-pad traversal can
/// reach both ends. The standard variant must be untouched: a
/// plain TextField, and anchors that add no focus node at all.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/app/variant.dart';
import 'package:tmhb/ui/settings_screen.dart';
import 'package:tmhb/ui/tv_focus.dart';

Widget _wrap(AppVariant variant, Widget child) {
  return ProviderScope(
    overrides: [appVariantProvider.overrideWithValue(variant)],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AppTextField on the standard variant', () {
    testWidgets('is a plain TextField', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? changed;
      await tester.pumpWidget(
        _wrap(
          AppVariant.standard,
          AppTextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'アドレス'),
            onChanged: (value) => changed = value,
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(EditableText), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nasne.local');
      expect(controller.text, 'nasne.local');
      expect(changed, 'nasne.local');
    });
  });

  group('AppTextField on the TV variant', () {
    testWidgets('shows the value without an editable field', (tester) async {
      final controller = TextEditingController(text: 'nasne.local');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(
          AppVariant.tv,
          AppTextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'アドレス'),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('nasne.local'), findsOneWidget);
    });

    testWidgets('focus alone opens neither keyboard nor dialog', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(
          AppVariant.tv,
          AppTextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'アドレス',
              hintText: '192.168.11.129',
            ),
          ),
        ),
      );
      // Move focus onto the field the way a remote would.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('OK opens the editor; confirming applies and refocuses', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'old');
      addTearDown(controller.dispose);
      String? changed;
      await tester.pumpWidget(
        _wrap(
          AppVariant.tv,
          AppTextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'アドレス'),
            onChanged: (value) => changed = value,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), '192.168.11.129');
      await tester.tap(find.text('決定'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.text, '192.168.11.129');
      expect(changed, '192.168.11.129');
      // Focus is back on the field: OK reopens the editor.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('cancelling the editor leaves the value untouched', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'keep');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(
          AppVariant.tv,
          AppTextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'アドレス'),
          ),
        ),
      );
      // The tap path opens the editor too.
      await tester.tap(find.byType(InputDecorator));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'discard me');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(controller.text, 'keep');
    });
  });

  group('TvFocusAnchor', () {
    Widget scrollFixture(AppVariant variant) {
      return _wrap(
        variant,
        ListView(
          children: [
            // A chain of focusable rows, like a real list: each
            // D-pad step scrolls a little further, building what
            // comes next, until the footer can take focus.
            for (var i = 0; i < 10; i++) ...[
              TextButton(onPressed: () {}, child: Text('行 $i')),
              const SizedBox(height: 100),
            ],
            const TvFocusAnchor(child: Text('末尾フッター')),
          ],
        ),
      );
    }

    Widget gapFixture(AppVariant variant) {
      return _wrap(
        variant,
        ListView(
          children: [
            TextButton(onPressed: () {}, child: const Text('先頭ボタン')),
            const SizedBox(height: 1200),
            const TvFocusAnchor(child: Text('末尾フッター')),
          ],
        ),
      );
    }

    testWidgets('TV: traversal reaches the footer and scrolls it in', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(scrollFixture(AppVariant.tv));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ListView));
      // The footer is far below: the ListView has not even
      // built it yet.
      expect(find.text('末尾フッター'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(find.text('末尾フッター'), findsOneWidget);
      final footerRect = tester.getRect(find.text('末尾フッター'));
      expect(footerRect.top, greaterThanOrEqualTo(viewport.top));
      expect(footerRect.bottom, lessThanOrEqualTo(viewport.bottom));
    });

    testWidgets('standard: the anchor adds no focus stop', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(gapFixture(AppVariant.standard));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      // Nothing below the button can take focus, so traversal
      // never scrolls: the footer is never even built.
      expect(find.text('末尾フッター'), findsNothing);
    });
  });

  group('settings screen on TV', () {
    testWidgets('the version footer is reachable by D-pad', (tester) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVariantProvider.overrideWithValue(AppVariant.tv),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final footer = find.textContaining('torne mobile HB バージョン');
      // Far below the fold: not built yet in the short viewport.
      expect(footer, findsNothing);
      final viewport = tester.getRect(find.byType(ListView));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        if (footer.evaluate().isNotEmpty) {
          final rect = tester.getRect(footer);
          if (rect.top >= viewport.top && rect.bottom <= viewport.bottom) {
            break;
          }
        }
      }
      expect(footer, findsOneWidget);
      final rect = tester.getRect(footer);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
    });
  });
}
