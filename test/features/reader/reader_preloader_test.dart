import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/reader/data/document_content_source.dart';
import 'package:folio/features/reader/logic/reader_preloader.dart';
import 'package:folio/features/reader/logic/reader_state.dart';

void main() {
  test('prime warms the document and adopt hands over the renderer once',
      () async {
    const path = '/prime/notes.txt';
    final document = DocumentEntry(
      id: path,
      source: const FileDocumentSource(path),
      name: 'Notes.txt',
      format: DocumentFormat.txt,
      sizeBytes: 11,
      modifiedAt: DateTime.utc(2026, 1, 1),
    );
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      path: Uint8List.fromList(utf8.encode('hello world')),
    });
    ReaderPreloader.resetForTest();

    ReaderPreloader.prime(document: document, contentSource: source);
    final renderer = ReaderPreloader.adopt(document);
    expect(renderer, isNotNull);
    expect(ReaderPreloader.adopt(document), isNull);

    for (var attempt = 0; attempt < 50; attempt++) {
      if (renderer!.loadState == ReaderLoadState.ready) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(renderer!.loadState, ReaderLoadState.ready);
    await renderer.close();
    renderer.dispose();
    ReaderPreloader.resetForTest();
  });

  test('prime ignores unavailable documents', () {
    const path = '/prime/missing.txt';
    final document = DocumentEntry(
      id: path,
      source: const FileDocumentSource(path),
      name: 'Missing.txt',
      format: DocumentFormat.txt,
      sizeBytes: 1,
      modifiedAt: DateTime.utc(2026, 1, 1),
      isAvailable: false,
    );
    ReaderPreloader.resetForTest();
    ReaderPreloader.prime(
      document: document,
      contentSource: MemoryDocumentContentSource(<String, Uint8List>{}),
    );
    expect(ReaderPreloader.adopt(document), isNull);
    ReaderPreloader.resetForTest();
  });
}
