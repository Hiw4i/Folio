import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/widgets/adaptive_glass_foreground.dart';
import 'package:folio/shared/glass/widgets/liquid_search_control.dart';

void _noop(String _) {}

void main() {
  testWidgets('typed query is mirrored through adaptive text', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (context) => const SizedBox(
                  width: 412,
                  height: 200,
                  child: LiquidSearchControl(onChanged: _noop),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    tester
        .state<LiquidSearchControlState>(find.byType(LiquidSearchControl))
        .open();
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('search_editable')),
      'hello',
    );
    await tester.pump();

    // Real editable keeps working and carries no visible glyphs itself.
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey<String>('search_editable')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.style.color, const Color(0x00FFFFFF));
    expect(editable.style.shadows, isNull);

    // Mirror shows the same query through the GPU black/white pipeline
    // (outlined fallback in the test env without shader filters).
    expect(find.widgetWithText(AdaptiveGlassText, 'hello'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
