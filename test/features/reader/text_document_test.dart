import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/reader/data/document_content_source.dart';
import 'package:folio/features/reader/data/text_document.dart';

void main() {
  DocumentEntry document(String path, DocumentFormat format) => DocumentEntry(
    id: path,
    source: FileDocumentSource(path),
    name: 'sample.${format.extension}',
    format: format,
    sizeBytes: 0,
    modifiedAt: DateTime.utc(2026, 9, 13),
  );

  test('strict UTF-8 decoding strips BOM and creates bounded chunks', () async {
    final text =
        '${List<String>.filled(6500, 'A').join()}\n'
        '${List<String>.filled(6500, 'B').join()}';
    final bytes = Uint8List.fromList(<int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(text),
    ]);
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      '/sample.txt': bytes,
    });

    final loaded = await TextDocumentLoader(source)
        .load(document('/sample.txt', DocumentFormat.txt));

    expect(loaded.text, text);
    expect(loaded.encoding, TextDocumentEncoding.utf8);
    expect(loaded.chunks.length, greaterThan(1));
    expect(loaded.chunks.map((chunk) => chunk.text).join(), text);
  });

  test('BOM-marked UTF-16 LE and BE are decoded strictly', () async {
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      '/little.txt': Uint8List.fromList(<int>[
        0xFF,
        0xFE,
        0x48,
        0,
        0x69,
        0,
        0x3D,
        0xD8,
        0x00,
        0xDE,
      ]),
      '/big.txt': Uint8List.fromList(<int>[0xFE, 0xFF, 0, 0x48, 0, 0x69]),
    });
    final loader = TextDocumentLoader(source);

    final little = await loader.load(
      document('/little.txt', DocumentFormat.txt),
    );
    final big = await loader.load(document('/big.txt', DocumentFormat.txt));

    expect(little.text, 'Hi😀');
    expect(little.encoding, TextDocumentEncoding.utf16LittleEndian);
    expect(big.text, 'Hi');
    expect(big.encoding, TextDocumentEncoding.utf16BigEndian);
  });

  test('malformed or unsupported bytes produce an explicit failure', () async {
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      '/sample.txt': Uint8List.fromList(<int>[0xC3, 0x28]),
    });

    expect(
      () =>
          TextDocumentLoader(source)
              .load(document('/sample.txt', DocumentFormat.txt)),
      throwsA(isA<UnsupportedTextEncodingException>()),
    );
  });

  test('empty files remain valid documents with no render chunks', () async {
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      '/empty.txt': Uint8List(0),
    });

    final loaded = await TextDocumentLoader(source)
        .load(document('/empty.txt', DocumentFormat.txt));

    expect(loaded.text, isEmpty);
    expect(loaded.chunks, isEmpty);
    expect(loaded.encoding, TextDocumentEncoding.utf8);
  });

  test(
    'large fenced Markdown is split while retaining render fences',
    () async {
      final markdown =
          '```dart\n'
          '${List<String>.filled(900, 'final value = 1;\n').join()}```\n';
      final source = MemoryDocumentContentSource(<String, Uint8List>{
        '/sample.md': Uint8List.fromList(utf8.encode(markdown)),
      });

      final loaded = await TextDocumentLoader(source)
          .load(document('/sample.md', DocumentFormat.markdown));

      expect(loaded.chunks.length, greaterThan(1));
      expect(loaded.chunks.first.renderSuffix, contains('```'));
      expect(loaded.chunks[1].renderPrefix, startsWith('```dart'));
      expect(loaded.chunks.map((chunk) => chunk.text).join(), markdown);
    },
  );
}
