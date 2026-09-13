import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/glass/liquid_search_control.dart';

void main() {
  testWidgets('search glass absorbs dragging before content behind it', (
    tester,
  ) async {
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
                onPanUpdate: (_) => backgroundDrags += 1,
              ),
              LiquidSearchControl(onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );

    final center = tester.getCenter(
      find.byKey(const ValueKey<String>('search_button_hit')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-32, 8));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(backgroundDrags, 0);
  });
}
