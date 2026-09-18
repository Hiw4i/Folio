import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/reader/data/document_content_source.dart';
import 'package:folio/features/reader/logic/reader_preloader.dart';
import 'package:folio/features/reader/logic/reader_state.dart';
import 'package:folio/features/reader/logic/renderer_lifecycle.dart';
import 'package:folio/features/reader/text/data/text_document.dart';
import 'package:folio/features/reader/text/logic/text_document_renderer.dart';

void main() {
  final document = _entry('one.txt');

  test(
    'query entered during open does not strand the reader in loading',
    () async {
      final source = _DelayedSource();
      final renderer = TextDocumentRenderer(
        document: document,
        loader: TextDocumentLoader(source),
      );
      addTearDown(renderer.dispose);
      final opening = renderer.open();
      await renderer.search('alpha');
      source.complete(0, 'Alpha beta ALPHA');
      await opening;
      expect(renderer.loadState, ReaderLoadState.ready);
      expect(renderer.query, 'alpha');
      expect(renderer.hitCount, 2);
      expect(renderer.isSearching, isFalse);
    },
  );

  test('superseded open cannot overwrite the newer document content', () async {
    final source = _DelayedSource();
    final renderer = TextDocumentRenderer(
      document: document,
      loader: TextDocumentLoader(source),
    );
    addTearDown(renderer.dispose);
    final oldOpen = renderer.open();
    final newOpen = renderer.open();
    source.complete(1, 'new content');
    await newOpen;
    source.complete(0, 'old content');
    await oldOpen;
    expect(renderer.content!.text, 'new content');
    expect(renderer.loadState, ReaderLoadState.ready);
  });

  test(
    'disposing during an outstanding read prevents late notifications',
    () async {
      final source = _DelayedSource();
      final renderer = TextDocumentRenderer(
        document: document,
        loader: TextDocumentLoader(source),
      );
      var notifications = 0;
      renderer.addListener(() => notifications++);
      final opening = renderer.open();
      renderer.dispose();
      final beforeCompletion = notifications;
      source.complete(0, 'late result');
      await opening;
      expect(notifications, beforeCompletion);
      expect(renderer.content, isNull);
      await renderer.search('late');
    },
  );

  test('latest query wins when large-document searches overlap', () async {
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      document.source.value: Uint8List.fromList(
        utf8.encode(List.filled(4000, 'needle ').join()),
      ),
    });
    final renderer = TextDocumentRenderer(
      document: document,
      loader: TextDocumentLoader(source),
    );
    addTearDown(renderer.dispose);
    await renderer.open();
    final first = renderer.search('needle');
    final last = renderer.search('absent');
    await Future.wait(<Future<void>>[first, last]);
    expect(renderer.query, 'absent');
    expect(renderer.hitCount, 0);
    expect(renderer.isSearching, isFalse);
  });

  test('speculative cache retains only one candidate', () async {
    final source = MemoryDocumentContentSource(<String, Uint8List>{
      document.source.value: Uint8List.fromList(utf8.encode('one')),
      '/two.txt': Uint8List.fromList(utf8.encode('two')),
    });
    addTearDown(ReaderPreloader.resetForTest);
    ReaderPreloader.prime(document: document, contentSource: source);
    ReaderPreloader.prime(document: _entry('two.txt'), contentSource: source);
    expect(ReaderPreloader.pendingCount, 1);
    expect(ReaderPreloader.adopt(document, contentSource: source), isNull);
    final renderer = ReaderPreloader.adopt(
      _entry('two.txt'),
      contentSource: source,
    );
    expect(renderer, isNotNull);
    expect(ReaderPreloader.pendingCount, 0);
    releaseDocumentRenderer(renderer!);
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'preloader cannot transfer a renderer across content-source instances',
    () async {
      final first = MemoryDocumentContentSource(<String, Uint8List>{
        document.source.value: Uint8List.fromList(utf8.encode('first')),
      });
      final second = MemoryDocumentContentSource(<String, Uint8List>{});
      addTearDown(ReaderPreloader.resetForTest);
      ReaderPreloader.prime(document: document, contentSource: first);
      expect(ReaderPreloader.adopt(document, contentSource: second), isNull);
      expect(ReaderPreloader.pendingCount, 0);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'preloader rejects a changed file size with unchanged timestamp',
    () async {
      final source = MemoryDocumentContentSource(<String, Uint8List>{
        document.source.value: Uint8List.fromList(utf8.encode('first')),
      });
      addTearDown(ReaderPreloader.resetForTest);
      ReaderPreloader.prime(document: document, contentSource: source);
      expect(
        ReaderPreloader.adopt(
          document.copyWith(sizeBytes: 999),
          contentSource: source,
        ),
        isNull,
      );
      ReaderPreloader.clear();
      await Future<void>.delayed(Duration.zero);
    },
  );
}

DocumentEntry _entry(String name) => DocumentEntry(
  id: '/$name',
  source: FileDocumentSource('/$name'),
  name: name,
  format: DocumentFormat.txt,
  sizeBytes: 64,
  modifiedAt: DateTime.utc(2026, 9, 18),
);

class _DelayedSource implements DocumentContentSource {
  final pending = <Completer<Uint8List>>[];

  @override
  Future<Uint8List> read(DocumentSource source) {
    final result = Completer<Uint8List>();
    pending.add(result);
    return result.future;
  }

  void complete(int index, String text) =>
      pending[index].complete(Uint8List.fromList(utf8.encode(text)));

  @override
  Future<PreparedPdfSource> preparePdf(DocumentSource source) async =>
      PreparedPdfData(bytes: await read(source));
}
