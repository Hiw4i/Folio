import 'package:flutter/material.dart' show DefaultMaterialLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/shared/selection/folio_selection_toolbar.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

void main() {
  Future<void> pumpToolbar(
    WidgetTester tester,
    List<ContextMenuButtonItem> buttonItems,
  ) {
    return tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          DefaultMaterialLocalizations.delegate,
        ],
        supportedLocales: const <Locale>[Locale('en')],
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
        ),
        home: FolioSelectionToolbar(
          anchors: const TextSelectionToolbarAnchors(
            primaryAnchor: Offset(100, 200),
          ),
          buttonItems: buttonItems,
        ),
      ),
    );
  }

  testWidgets('shows copy and select-all as lucide icons without text', (
    tester,
  ) async {
    await pumpToolbar(tester, <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.copy,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.selectAll,
      ),
    ]);
    await tester.pump();

    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
    expect(find.byIcon(LucideIcons.textSelect), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Select all'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filters out unrelated system actions', (tester) async {
    await pumpToolbar(tester, <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.cut,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.copy,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.paste,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.share,
      ),
    ]);
    await tester.pump();

    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
    expect(find.byIcon(LucideIcons.textSelect), findsNothing);
    expect(find.text('Cut'), findsNothing);
    expect(find.text('Paste'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing without copy or select-all', (tester) async {
    await pumpToolbar(tester, <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.share,
      ),
    ]);
    await tester.pump();

    expect(find.byIcon(LucideIcons.copy), findsNothing);
    expect(find.byIcon(LucideIcons.textSelect), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the copy icon invokes its action', (tester) async {
    var activations = 0;
    await pumpToolbar(tester, <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () => activations += 1,
        type: ContextMenuButtonType.copy,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.selectAll,
      ),
    ]);
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Copy'));
    await tester.pumpAndSettle();

    expect(activations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the select-all icon invokes its action', (
    tester,
  ) async {
    var activations = 0;
    await pumpToolbar(tester, <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.copy,
      ),
      ContextMenuButtonItem(
        onPressed: () => activations += 1,
        type: ContextMenuButtonType.selectAll,
      ),
    ]);
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Select all'));
    await tester.pumpAndSettle();

    expect(activations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pill surface keeps full painted size (icons stay inside)', (
    tester,
  ) async {
    await pumpToolbar(tester, <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.copy,
      ),
      ContextMenuButtonItem(
        onPressed: () {},
        type: ContextMenuButtonType.selectAll,
      ),
    ]);
    await tester.pump();

    // Пилюля: 2 кнопки 36 + разделитель 9 + паддинги 2x4 = 89x44,
    // живописный бокс единой поверхности — плюс paintPadding (40)
    // с каждой стороны, как у остальных liquid-контролов.
    // Без OverflowBox внутренний бокс схлопывается до 89x44 и стеклянный
    // path съезжает относительно иконок.
    const pillWidth = 4.0 * 2 + 36.0 * 2 + 9.0;
    const expectedSurface = Size(pillWidth + 40 * 2, 44 + 40 * 2);
    final surfaces = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.width == expectedSurface.width,
    );
    expect(surfaces, findsOneWidget);
    expect(tester.getSize(surfaces), expectedSurface);

    // Иконки лежат внутри пилюли, на одной горизонтали, copy слева.
    final pills = find.byWidgetPredicate(
      (widget) =>
          widget is SizedBox &&
          widget.width == pillWidth &&
          widget.height == 44,
    );
    expect(pills, findsOneWidget);
    final pillRect = tester.getRect(pills);
    final copyRect = tester.getRect(
      find.byKey(const ValueKey<String>('folio_toolbar_copy')),
    );
    final selectAllRect = tester.getRect(
      find.byKey(const ValueKey<String>('folio_toolbar_select_all')),
    );
    expect(copyRect.center.dy, moreOrLessEquals(pillRect.center.dy, epsilon: 1));
    expect(
      selectAllRect.center.dy,
      moreOrLessEquals(pillRect.center.dy, epsilon: 1),
    );
    expect(copyRect.center.dx, lessThan(selectAllRect.center.dx));
    expect(
      (copyRect.center.dx + selectAllRect.center.dx) / 2,
      moreOrLessEquals(pillRect.center.dx, epsilon: 1),
    );
    expect(tester.takeException(), isNull);
  });
}
