/// Widget test for the tap-outside keyboard dismissal
/// (plan 54): tapping a text field focuses it, and tapping
/// outside must release the focus — the dismissal path that
/// did not exist when the iOS software keyboard got trapped
/// on screen from the manual registration field.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tmhb/ui/widgets.dart';

void main() {
  testWidgets('tap outside a focused field dismisses the keyboard', (
    tester,
  ) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardDismissOnTap(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focusNode),
                const SizedBox(height: 200, child: Text('outside')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    await tester.tap(find.text('outside'));
    await tester.pump();
    expect(focusNode.hasFocus, isFalse);
  });
}
