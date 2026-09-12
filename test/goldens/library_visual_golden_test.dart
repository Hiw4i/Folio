import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/folio_app.dart';
import 'package:folio/shared/glass/liquid_search_control.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await inter.load();
  });

  testWidgets('library and liquid search visual states', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const FolioApp());
    await tester.pumpAndSettle();
    final surface = find.byKey(const ValueKey<String>('folio_surface'));

    await expectLater(
      surface,
      matchesGoldenFile('library_search_collapsed.png'),
    );

    await tester.tap(find.text('PPTX'));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 15));
    }
    await expectLater(
      surface,
      matchesGoldenFile('library_filter_morphing.png'),
    );
    await tester.pumpAndSettle();
    await expectLater(
      surface,
      matchesGoldenFile('library_filter_selected.png'),
    );
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey<String>('search_button_hit'));
    final gesture = await tester.startGesture(tester.getCenter(search));
    await tester.pump(const Duration(milliseconds: 80));
    await expectLater(surface, matchesGoldenFile('library_search_pressed.png'));

    await gesture.cancel();
    await tester.pumpAndSettle();
    tester
        .state<LiquidSearchControlState>(find.byType(LiquidSearchControl))
        .open();
    await tester.pump(const Duration(milliseconds: 150));
    await expectLater(
      surface,
      matchesGoldenFile('library_search_morphing.png'),
    );

    await tester.pumpAndSettle();
    await expectLater(
      surface,
      matchesGoldenFile('library_search_expanded.png'),
    );
  });
}
