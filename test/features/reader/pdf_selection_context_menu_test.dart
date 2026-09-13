import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/reader/widgets/pdf_document_view.dart';

void main() {
  testWidgets('PDF selection toolbar provides its own Material localization', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        ),
        home: PdfSelectionContextMenu(
          primaryAnchor: const Offset(80, 120),
          buttonItems: <ContextMenuButtonItem>[
            ContextMenuButtonItem(
              onPressed: () {},
              type: ContextMenuButtonType.copy,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
