import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/reader/data/document_content_source.dart';
import 'package:folio/features/reader/logic/document_renderer.dart';
import 'package:folio/features/reader/logic/reader_state.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  const path = '/documents/sample.pdf';
  final document = DocumentEntry(
    id: path,
    source: const FileDocumentSource(path),
    name: 'Sample.pdf',
    format: DocumentFormat.pdf,
    sizeBytes: 5,
    modifiedAt: DateTime.utc(2026, 9, 13),
  );

  test(
    'PDF renderer prepares a progressive data source without opening it',
    () async {
      final renderer = PdfDocumentRenderer(
        document: document,
        contentSource: MemoryDocumentContentSource(<String, Uint8List>{
          path: Uint8List.fromList(<int>[37, 80, 68, 70, 45]),
        }),
      );
      addTearDown(renderer.dispose);

      await renderer.open();

      expect(renderer.sourceReady, isTrue);
      expect(renderer.documentRef, isA<PdfDocumentRefData>());
      expect(renderer.loadState, ReaderLoadState.loading);
      expect(renderer.positionLabel, 'PDF');
    },
  );

  test('PDF renderer preserves typed source failures', () async {
    final renderer = PdfDocumentRenderer(
      document: document,
      contentSource: _FailingPdfSource(),
    );
    addTearDown(renderer.dispose);

    await renderer.open();

    expect(renderer.loadState, ReaderLoadState.failed);
    expect(renderer.failure?.kind, ReaderFailureKind.accessDenied);
    expect(renderer.failure?.canRetry, isTrue);
  });

  test('closing the renderer releases its prepared PDF source', () async {
    final source = _DisposablePdfSource();
    final renderer = PdfDocumentRenderer(
      document: document,
      contentSource: source,
    );

    await renderer.open();
    await renderer.close();
    renderer.dispose();

    expect(source.closeCount, 1);
    expect(renderer.sourceReady, isFalse);
  });
}

class _FailingPdfSource implements DocumentContentSource {
  @override
  Future<PreparedPdfSource> preparePdf(DocumentSource source) {
    throw const DocumentReadException(
      DocumentReadFailureKind.denied,
      'Denied for test.',
    );
  }

  @override
  Future<Uint8List> read(DocumentSource source) {
    throw UnimplementedError();
  }
}

class _DisposablePdfSource implements DocumentContentSource {
  int closeCount = 0;

  @override
  Future<PreparedPdfSource> preparePdf(DocumentSource source) async {
    return PreparedPdfRandomAccess(
      length: 2048,
      readRange: (position, size) async => Uint8List(size),
      onClose: () async {
        closeCount += 1;
      },
    );
  }

  @override
  Future<Uint8List> read(DocumentSource source) {
    throw UnimplementedError();
  }
}
