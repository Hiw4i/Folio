import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/widgets/scroll_edge_fade.dart';

void main() {
  testWidgets('keeps constant 13 percent fades without intercepting taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            height: 200,
            child: ScrollEdgeFade(
              color: const Color(0xFF101112),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps += 1,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(ScrollEdgeFade.topKey)).height, 26);
    expect(tester.getSize(find.byKey(ScrollEdgeFade.bottomKey)).height, 26);

    await tester.tapAt(tester.getCenter(find.byKey(ScrollEdgeFade.topKey)));
    expect(taps, 1);
  });
}
