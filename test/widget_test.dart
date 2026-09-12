import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/folio_app.dart';

void main() {
  testWidgets('catalog filters and liquid search update visible documents', (
    tester,
  ) async {
    await tester.pumpWidget(const FolioApp());
    await tester.pump();

    expect(find.text('Folio'), findsOneWidget);
    expect(find.byType(FadingEdgeScrollView), findsOneWidget);
    expect(find.text('RECENT'), findsOneWidget);
    expect(find.text('Product principles.pdf'), findsOneWidget);

    await tester.tap(find.text('PPTX'));
    await tester.pumpAndSettle();
    expect(find.text('Roadmap.pptx'), findsOneWidget);
    expect(find.text('Annual report.pdf'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(
      find.byKey(const ValueKey<String>('search_editable')),
      'launch',
    );
    await tester.pump();

    expect(find.text('Launch review.pptx'), findsOneWidget);
    expect(find.text('Roadmap.pptx'), findsNothing);
    expect(find.text('RESULTS'), findsOneWidget);
  });
}
