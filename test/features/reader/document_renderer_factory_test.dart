import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/reader/data/document_content_source.dart';
import 'package:folio/features/reader/logic/document_renderer.dart';

void main() {
  final contentSource = MemoryDocumentContentSource(<String, Uint8List>{});

  DocumentEntry document(DocumentFormat format) => DocumentEntry(
    id: '/documents/sample.${format.extension}',
    source: FileDocumentSource('/documents/sample.${format.extension}'),
    name: 'sample.${format.extension}',
    format: format,
    sizeBytes: 0,
    modifiedAt: DateTime.utc(2026, 9, 13),
  );

  test('factory routes each format to its dedicated renderer', () {
    expect(
      createDocumentRenderer(
        document: document(DocumentFormat.pdf),
        contentSource: contentSource,
      ),
      isA<PdfDocumentRenderer>(),
    );
    expect(
      createDocumentRenderer(
        document: document(DocumentFormat.docx),
        contentSource: contentSource,
      ),
      isA<WordDocumentRenderer>(),
    );
    expect(
      createDocumentRenderer(
        document: document(DocumentFormat.pptx),
        contentSource: contentSource,
      ),
      isA<PowerPointDocumentRenderer>(),
    );
    expect(
      createDocumentRenderer(
        document: document(DocumentFormat.txt),
        contentSource: contentSource,
      ),
      isA<TextDocumentRenderer>(),
    );
  });
}
