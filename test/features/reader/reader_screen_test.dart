import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/app/folio_app.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/library/data/in_memory_library_repository.dart';
import 'package:folio/features/reader/data/document_content_source.dart';
import 'package:folio/shared/glass/liquid_glass_control.dart';
import 'package:folio/shared/glass/liquid_search_control.dart';

void main() {
  const path = '/documents/notes.txt';
  final document = DocumentEntry(
    id: path,
    source: const FileDocumentSource(path),
    name: 'Notes.txt',
    format: DocumentFormat.txt,
    sizeBytes: 120,
    modifiedAt: DateTime.utc(2026, 9, 13),
  );

  Future<void> openReader(WidgetTester tester) async {
    await tester.pumpWidget(
      FolioApp(
        libraryRepository: InMemoryLibraryRepository(
          documents: <DocumentEntry>[document],
        ),
        documentContentSource: MemoryDocumentContentSource(<String, Uint8List>{
          path: Uint8List.fromList(
            utf8.encode(
              'Quiet text.\n\nSearch target and another target.\n\n'
              '${List<String>.filled(90, 'A calm line for scrolling.\n\n').join()}',
            ),
          ),
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes.txt'));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find
          .byKey(const ValueKey<String>('reader_content'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  testWidgets('catalog opens TXT in the reader and searches its text', (
    tester,
  ) async {
    await openReader(tester);

    expect(
      find.byKey(const ValueKey<String>('reader_surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('reader_content')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.textSpan?.toPlainText() ?? '').contains('Quiet text.'),
      ),
      findsOneWidget,
    );

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('search_button_hit'))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('search_editable')),
      'target',
    );
    await tester.pump(const Duration(milliseconds: 200));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.text('1 of 2').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('reader_next_hit')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('Back closes keyboard, search, then reader route', (
    tester,
  ) async {
    await openReader(tester);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('search_button_hit'))),
    );
    await tester.pumpAndSettle();
    final searchState = tester.state<LiquidSearchControlState>(
      find.byType(LiquidSearchControl),
    );
    expect(searchState.isExpanded, isTrue);
    expect(find.text('0%'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search field');

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('reader_surface')),
      findsOneWidget,
    );
    expect(searchState.isExpanded, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reader_surface')),
      findsOneWidget,
    );
    expect(searchState.isExpanded, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Folio'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reader_surface')), findsNothing);
  });

  testWidgets('tapping an expanded search field restores input focus', (
    tester,
  ) async {
    await openReader(tester);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey<String>('search_button_hit'))),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot('Search field'),
    );

    await tester.tap(find.byKey(const ValueKey<String>('search_editable')));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Search field');
    expect(
      tester
          .state<LiquidSearchControlState>(find.byType(LiquidSearchControl))
          .isExpanded,
      isTrue,
    );
  });

  testWidgets('reader menu shows file information', (tester) async {
    await openReader(tester);

    await tester.tap(find.byKey(const ValueKey<String>('reader_menu_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('File info'));
    await tester.pumpAndSettle();

    expect(find.text('File info'), findsOneWidget);
    expect(find.text('TXT'), findsOneWidget);
    expect(find.text('120 B'), findsOneWidget);
  });

  testWidgets('reader menu morph closes after an outside tap', (tester) async {
    await openReader(tester);

    await tester.tap(find.byKey(const ValueKey<String>('reader_menu_button')));
    await tester.pumpAndSettle();
    expect(find.text('Remove from Recents'), findsOneWidget);

    await tester.tapAt(const Offset(24, 430));
    await tester.pumpAndSettle();
    expect(find.text('Remove from Recents'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reader_menu_button')),
      findsOneWidget,
    );
  });

  testWidgets('title and progress use deformable liquid surfaces', (
    tester,
  ) async {
    await openReader(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reader_title_glass')),
        matching: find.byType(LiquidGlassControl),
      ),
      findsOneWidget,
    );
    final titleSize = tester.getSize(
      find.byKey(const ValueKey<String>('reader_title_glass')),
    );
    expect(titleSize.height, 42);
    expect(titleSize.width, lessThan(180));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reader_progress_glass')),
        matching: find.byType(LiquidGlassControl),
      ),
      findsOneWidget,
    );
  });

  testWidgets('chrome hides on downward scroll and returns on content tap', (
    tester,
  ) async {
    await openReader(tester);
    final topChrome = find.byKey(const ValueKey<String>('reader_top_chrome'));

    await tester.drag(
      find.byKey(const ValueKey<String>('reader_content')),
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(of: topChrome, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isTrue,
    );

    await tester.tapAt(const Offset(200, 430));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(of: topChrome, matching: find.byType(IgnorePointer))
                .first,
          )
          .ignoring,
      isFalse,
    );
  });

  testWidgets('Markdown renders locally and blocks remote image loading', (
    tester,
  ) async {
    const markdownPath = '/documents/notes.md';
    final markdownDocument = DocumentEntry(
      id: markdownPath,
      source: const FileDocumentSource(markdownPath),
      name: 'Notes.md',
      format: DocumentFormat.markdown,
      sizeBytes: 180,
      modifiedAt: DateTime.utc(2026, 9, 13),
    );
    await tester.pumpWidget(
      FolioApp(
        libraryRepository: InMemoryLibraryRepository(
          documents: <DocumentEntry>[markdownDocument],
        ),
        documentContentSource: MemoryDocumentContentSource(<String, Uint8List>{
          markdownPath: Uint8List.fromList(
            utf8.encode(
              '# Local notes\n\nA **quiet** reader.\n\n'
              '![Remote illustration](https://example.com/image.png)',
            ),
          ),
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes.md'));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find
          .byKey(const ValueKey<String>('reader_content'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(find.text('Local notes'), findsOneWidget);
    expect(find.text('Remote illustration'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    tester
        .state<LiquidSearchControlState>(find.byType(LiquidSearchControl))
        .open();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(
      find.byKey(const ValueKey<String>('search_editable')),
      'quiet',
    );
    await tester.pump(const Duration(milliseconds: 200));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      if (find.text('1 of 1').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);
  });
}
