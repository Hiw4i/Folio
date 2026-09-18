import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_entry.dart';
import 'package:folio/features/library/data/document_scanner.dart';
import 'package:folio/features/library/data/file_library_repository.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/features/library/logic/library_controller.dart';
import 'package:folio/shared/android/android_storage_gateway.dart';

void main() {
  test('derived lists are reused until their input changes', () async {
    final controller = LibraryController(repository: _Repository());
    addTearDown(controller.dispose);
    await controller.load();
    await controller.refresh();
    final matches = controller.matches;
    final regular = controller.regularDocuments;
    expect(identical(controller.matches, matches), isTrue);
    expect(identical(controller.regularDocuments, regular), isTrue);
    expect(() => matches.clear(), throwsUnsupportedError);
    controller.updateQuery('ALPHA');
    expect(controller.matches.single.name, 'Alpha.txt');
    expect(identical(controller.matches, matches), isFalse);
    expect(controller.recentDocuments, isEmpty);
  });

  test(
    'overlapping refresh requests share one scan and preserve updates',
    () async {
      final repository = _Repository()..holdScan = true;
      final controller = LibraryController(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await Future<void>.delayed(Duration.zero);
      final first = controller.refresh();
      final second = controller.refresh();
      expect(identical(first, second), isTrue);
      expect(repository.refreshCalls, 1);
      repository.scans.add(
        LibrarySnapshot(
          documents: <DocumentEntry>[_entry('New.pdf')],
          access: LibraryAccess.granted,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.matches.single.name, 'New.pdf');
      await repository.scans.close();
      await first;
      expect(controller.isRefreshing, isFalse);
    },
  );

  test('late initial intent cannot notify a disposed controller', () async {
    final repository = _Repository()..initialGate = Completer<DocumentEntry?>();
    final controller = LibraryController(repository: repository);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final loading = controller.load();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    final before = notifications;
    repository.initialGate!.complete(_entry('Late.txt'));
    await loading;
    expect(notifications, before);
    expect(controller.pendingDocument, isNull);
  });

  test(
    'history persistence failure does not block a readable document',
    () async {
      final repository = _Repository()..failHistory = true;
      final controller = LibraryController(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.refresh();
      final entry = controller.matches.first;
      await controller.open(entry);
      expect(controller.pendingDocument!.id, entry.id);
      expect(controller.recentDocuments.first.lastOpenedAt, isNotNull);
    },
  );

  test('dismissed recovery cannot push a late replacement reader', () async {
    final repository = _Repository()
      ..recoveryGate = Completer<DocumentEntry?>();
    final controller = LibraryController(repository: repository);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.refresh();
    await controller.open(_entry('Missing.txt').copyWith(isAvailable: false));
    final recovering = controller.recoverUnavailable();
    controller.dismissUnavailable();
    repository.recoveryGate!.complete(_entry('Recovered.txt'));
    await recovering;
    expect(controller.pendingDocument, isNull);
    expect(controller.unavailableDocument, isNull);
  });

  test(
    'one corrupt cache row does not discard history and old path IDs migrate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'folio-cache-regression-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final document = _entry('MixedCase.txt')
          .copyWith(lastOpenedAt: DateTime.utc(2026));
      final encoded = document.toJson()..['id'] = document.id.toLowerCase();
      await File('${directory.path}/library_catalog.v1.json').writeAsString(
        jsonEncode(<String, Object?>{
          'version': 1,
          'documents': <Object?>[
            encoded,
            <String, Object?>{'broken': true},
          ],
        }),
      );
      final repository = FileLibraryRepository(
        storageGateway: _Storage(),
        cacheDirectoryProvider: () async => directory,
      );
      addTearDown(repository.dispose);
      final loaded = await repository.load();
      expect(loaded.documents, hasLength(1));
      expect(loaded.documents.single.id, document.id);
      expect(loaded.documents.single.lastOpenedAt, document.lastOpenedAt);
    },
  );

  test(
    'cache write failure is observable but does not fail markOpened',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'folio-cache-error-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final blocked = File('${directory.path}/blocked');
      await blocked.writeAsString('must survive');
      final repository = FileLibraryRepository(
        storageGateway: _Storage(),
        cacheDirectoryProvider: () async => Directory(blocked.path),
      );
      addTearDown(repository.dispose);
      final opened = await repository.markOpened(_entry('Available.txt'));
      expect(opened.lastOpenedAt, isNotNull);
      expect(repository.lastCacheWriteError, isNotNull);
      expect(await blocked.readAsString(), 'must survive');
    },
  );

  test(
    'scanner deduplicates overlapping roots and preserves filename case',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'folio-scan-regression-',
      );
      addTearDown(() => root.delete(recursive: true));
      final nested = await Directory('${root.path}/nested').create();
      await File('${nested.path}/Case.txt').writeAsString('one');
      await File('${nested.path}/case.txt').writeAsString('two');
      final batches = await const IsolateDocumentScanner(batchSize: 1)
          .scan(<String>[root.path, nested.path, root.path])
          .toList();
      final documents = batches.expand((batch) => batch.documents).toList();
      // Linux/Android paths are case-sensitive. On a case-insensitive volume
      // only one physical file exists, so compare to actual Directory results.
      final physicalFiles = await nested
          .list()
          .where((entity) => entity is File)
          .length;
      expect(documents, hasLength(physicalFiles));
      expect(
        documents.map((document) => document.id).toSet(),
        hasLength(physicalFiles),
      );
      expect(batches.where((batch) => batch.isComplete), hasLength(1));
    },
  );

  test('scanner supports cancellation before isolate spawn resolves', () async {
    final root = await Directory.systemTemp.createTemp('folio-scan-cancel-');
    addTearDown(() => root.delete(recursive: true));
    var deliveries = 0;
    final subscription = const IsolateDocumentScanner()
        .scan(<String>[root.path])
        .listen((_) => deliveries++);
    await subscription.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(deliveries, 0);
  });

  test('case-distinct file paths never share a generated document ID', () {
    expect(
      stableDocumentId(const FileDocumentSource('/docs/A.txt')),
      isNot(stableDocumentId(const FileDocumentSource('/docs/a.txt'))),
    );
  });
}

DocumentEntry _entry(String name) {
  final source = FileDocumentSource('/docs/$name');
  return DocumentEntry(
    id: stableDocumentId(source),
    source: source,
    name: name,
    format: DocumentFormatPresentation.fromFileName(name)!,
    sizeBytes: 10,
    modifiedAt: DateTime.utc(2026, 9, 18),
  );
}

class _Repository implements LibraryRepository {
  final scans = StreamController<LibrarySnapshot>();
  bool holdScan = false;
  bool failHistory = false;
  int refreshCalls = 0;
  Completer<DocumentEntry?>? initialGate;
  Completer<DocumentEntry?>? recoveryGate;

  @override
  Future<LibrarySnapshot> load() async => LibrarySnapshot(
    documents: <DocumentEntry>[_entry('Beta.pdf'), _entry('Alpha.txt')],
    access: LibraryAccess.granted,
  );

  @override
  Stream<LibrarySnapshot> refresh() {
    refreshCalls++;
    return holdScan ? scans.stream : const Stream<LibrarySnapshot>.empty();
  }

  @override
  Future<DocumentEntry?> consumeInitialDocument() =>
      initialGate?.future ?? Future<DocumentEntry?>.value(null);

  @override
  Stream<DocumentEntry> get incomingDocuments =>
      const Stream<DocumentEntry>.empty();

  @override
  Future<DocumentEntry> markOpened(DocumentEntry document) async {
    if (failHistory) throw const FileSystemException('History unavailable');
    return document.copyWith(lastOpenedAt: DateTime.now());
  }

  @override
  Future<DocumentEntry?> recoverAccess(DocumentEntry document) =>
      recoveryGate?.future ?? Future<DocumentEntry?>.value(null);

  @override
  Future<void> removeFromRecents(DocumentEntry document) async {}

  @override
  Future<void> requestFullAccess() async {}

  @override
  void dispose() {
    if (!scans.isClosed) unawaited(scans.close());
  }
}

class _Storage implements StorageGateway {
  @override
  Future<bool> hasAllFilesAccess() async => false;
  @override
  Future<List<StorageRoot>> storageRoots() async => const <StorageRoot>[];
  @override
  Future<IncomingDocument?> consumeInitialDocument() async => null;
  @override
  Stream<IncomingDocument> get incomingDocuments =>
      const Stream<IncomingDocument>.empty();
  @override
  Future<void> openAllFilesSettings() async {}
  @override
  Future<IncomingDocument?> requestDocumentAccess({
    required String displayName,
    String? mimeType,
  }) async => null;
}
