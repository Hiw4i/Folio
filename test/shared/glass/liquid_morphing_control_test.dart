import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/widgets/liquid_morphing_control.dart';

void main() {
  Widget buildHarness({required ValueChanged<int> onBackgroundDrag}) {
    return MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (_) => onBackgroundDrag(1),
            ),
            LiquidMorphingControl(
              collapsedHitKey: const ValueKey<String>('morph_hit'),
              collapsedSemanticsLabel: 'Open menu',
              expandedSemanticsLabel: 'Menu',
              geometryBuilder: (size) => LiquidMorphGeometry(
                collapsedRect: const Rect.fromLTWH(300, 20, 48, 48),
                expandedRect: const Rect.fromLTWH(140, 20, 208, 116),
              ),
              collapsedChild: const Center(child: Text('•••')),
              expandedChild: const Center(child: Text('Menu content')),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('morphing glass absorbs a drag before content behind it', (
    tester,
  ) async {
    var backgroundDrags = 0;
    await tester.pumpWidget(
      buildHarness(onBackgroundDrag: (value) => backgroundDrags += value),
    );

    final center = tester.getCenter(
      find.byKey(const ValueKey<String>('morph_hit')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-34, 8));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(backgroundDrags, 0);
  });

  testWidgets('menu content receives velocity blur during its spring morph', (
    tester,
  ) async {
    await tester.pumpWidget(buildHarness(onBackgroundDrag: (_) {}));
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('morph_hit'))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.byType(ImageFiltered), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Menu content'), findsOneWidget);
  });
}
