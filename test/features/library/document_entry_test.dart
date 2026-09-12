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
}
