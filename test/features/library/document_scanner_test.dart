import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_scanner.dart';

void main() {
  test(
    'scanner emits bounded batches and skips unsupported/protected paths',
    () async {
      final root = await Directory.systemTemp.createTemp('folio-scan-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      await File('${root.path}/Report.PDF').writeAsString('pdf');
      await File('${root.path}/Notes.md').writeAsString('markdown');
      await File('${root.path}/Legacy.doc').writeAsString('legacy');
      final protected = Directory('${root.path}/Android/data/example')
        ..createSync(recursive: true);
      await File('${protected.path}/Hidden.pdf').writeAsString('hidden');

      final batches = await const IsolateDocumentScanner(batchSize: 1)
          .scan(<String>[root.path])
          .toList();
      final documents = batches
          .expand((batch) => batch.documents)
          .toList(growable: false);

      expect(batches.where((batch) => !batch.isComplete), hasLength(2));
      expect(batches.last.isComplete, isTrue);
      expect(documents.map((document) => document.name).toSet(), <String>{
        'Report.PDF',
        'Notes.md',
      });
      expect(
        documents.map((document) => document.name),
        isNot(contains('Hidden.pdf')),
      );
      expect(
        documents.map((document) => document.name),
        isNot(contains('Legacy.doc')),
      );
    },
  );

  test('scanner isolate is cancelled when its listener stops early', () async {
    final root = await Directory.systemTemp.createTemp('folio-cancel-scan-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    for (var index = 0; index < 24; index++) {
      await File('${root.path}/Document-$index.pdf').writeAsString('$index');
    }

    final firstBatch = await const IsolateDocumentScanner(batchSize: 1)
        .scan(<String>[root.path])
        .first;

    expect(firstBatch.documents, hasLength(1));
    expect(firstBatch.isComplete, isFalse);
  });
}
