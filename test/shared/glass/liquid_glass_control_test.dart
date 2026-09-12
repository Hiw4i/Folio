import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/liquid_glass_control.dart';

void main() {
  testWidgets('generic liquid control accepts arbitrary content and activates', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: LiquidGlassControl(
              semanticsLabel: 'More options',
              size: const Size(56, 56),
              onTap: () => activations += 1,
              child: const SizedBox(
                key: ValueKey<String>('custom_liquid_content'),
                width: 18,
                height: 18,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('custom_liquid_content')),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('More options'));
    await tester.pumpAndSettle();
    expect(activations, 1);
  });
}
