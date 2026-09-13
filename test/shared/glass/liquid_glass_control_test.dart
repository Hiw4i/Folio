import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/liquid_glass_control.dart';

void main() {
  testWidgets(
    'generic liquid control accepts arbitrary content and activates',
    (tester) async {
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
    },
  );

  testWidgets('arbitrary content follows the dragged liquid material', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: LiquidGlassControl(
              size: Size(180, 50),
              child: SizedBox(
                key: ValueKey<String>('passive_liquid_content'),
                width: 60,
                height: 18,
              ),
            ),
          ),
        ),
      ),
    );

    final content = find.byKey(
      const ValueKey<String>('passive_liquid_content'),
    );
    final initialCenter = tester.getCenter(content);
    final gesture = await tester.startGesture(initialCenter);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(28, 8));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      (tester.getCenter(content) - initialCenter).distance,
      greaterThan(0.2),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('glass absorbs taps and drags before content behind it', (
    tester,
  ) async {
    var glassTaps = 0;
    var backgroundTaps = 0;
    var backgroundDrags = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => backgroundTaps += 1,
                onPanUpdate: (_) => backgroundDrags += 1,
              ),
              Center(
                child: LiquidGlassControl(
                  semanticsLabel: 'Blocking glass',
                  size: const Size(120, 52),
                  onTap: () => glassTaps += 1,
                  child: const Text('Glass'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final glass = find.text('Glass');
    final glassCenter = tester.getCenter(glass);
    await tester.tapAt(glassCenter);
    await tester.pumpAndSettle();
    expect(glassTaps, 1);
    expect(backgroundTaps, 0);

    final gesture = await tester.startGesture(glassCenter);
    await gesture.moveBy(const Offset(28, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(backgroundDrags, 0);
  });
}
