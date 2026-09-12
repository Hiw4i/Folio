import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';

void main() {
  group('DocumentFormatPresentation.fromFileName', () {
    test('recognizes only the five v1 formats case-insensitively', () {
      expect(
        DocumentFormatPresentation.fromFileName('Report.PDF'),
        DocumentFormat.pdf,
      );
      expect(
        DocumentFormatPresentation.fromFileName('Draft.docx'),
        DocumentFormat.docx,
      );
      expect(
        DocumentFormatPresentation.fromFileName('Deck.PptX'),
        DocumentFormat.pptx,
      );
      expect(
        DocumentFormatPresentation.fromFileName('Notes.txt'),
        DocumentFormat.txt,
      );
      expect(
        DocumentFormatPresentation.fromFileName('README.md'),
        DocumentFormat.markdown,
      );
    });

    test('rejects legacy and unsupported extensions', () {
      expect(DocumentFormatPresentation.fromFileName('Legacy.doc'), isNull);
      expect(DocumentFormatPresentation.fromFileName('Legacy.ppt'), isNull);
      expect(DocumentFormatPresentation.fromFileName('Sheet.xlsx'), isNull);
      expect(DocumentFormatPresentation.fromFileName('No extension'), isNull);
    });
  });

  test('cache JSON preserves path and content URI identity', () {
    final openedAt = DateTime.utc(2026, 9, 13, 9, 30);
    final pathSource = const FileDocumentSource(
      r'/storage/emulated/0/Documents/Report.PDF',
    );
    final original = DocumentEntry(
      id: stableDocumentId(pathSource),
      source: pathSource,
      name: 'Report.PDF',
      format: DocumentFormat.pdf,
      sizeBytes: 4096,
      modifiedAt: DateTime.utc(2026, 9, 12),
      lastOpenedAt: openedAt,
      isAvailable: false,
    );

    final decoded = DocumentEntry.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.source, isA<FileDocumentSource>());
    expect(decoded.source.value, pathSource.path);
    expect(decoded.lastOpenedAt, openedAt);
    expect(decoded.isAvailable, isFalse);
    expect(
      stableDocumentId(const UriDocumentSource('content://files/42')),
      'uri:content://files/42',
    );
  });
}
