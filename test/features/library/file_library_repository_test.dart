import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folio/features/library/data/document_scanner.dart';
import 'package:folio/features/library/data/file_library_repository.dart';
import 'package:folio/features/library/data/library_repository.dart';
import 'package:folio/shared/platform/android_storage_gateway.dart';

void main() {
  test(
    'scan is cached and a missing Recent file is retained unavailable',
    () async {
      final root = await Directory.systemTemp.createTemp('folio-library-');
      final cache = await Directory.systemTemp.createTemp('folio-cache-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
        if (await cache.exists()) {
          await cache.delete(recursive: true);
        }
      });
      final sourceFile = File('${root.path}/Guide.pdf');
      await sourceFile.writeAsString('document');
      await File('${root.path}/Ignored.ppt').writeAsString('legacy');
      final gateway = _FakeStorageGateway(
        hasAccess: true,
        roots: <StorageRoot>[StorageRoot(path: root.path, isRemovable: false)],
      );
      final repository = FileLibraryRepository(
        storageGateway: gateway,
        scanner: const IsolateDocumentScanner(batchSize: 1),
        cacheDirectoryProvider: () async => cache,
        now: () => DateTime.utc(2026, 9, 13, 12),
      );

      final firstScan = await repository.refresh().toList();
      final discovered = firstScan.last.documents.single;
      expect(discovered.name, 'Guide.pdf');
      await repository.markOpened(discovered);
      await sourceFile.delete();

      final secondScan = await repository.refresh().toList();
      expect(secondScan.last.documents.single.isAvailable, isFalse);
      repository.dispose();

      final deniedRepository = FileLibraryRepository(
        storageGateway: _FakeStorageGateway(hasAccess: false),
        cacheDirectoryProvider: () async => cache,
      );
      final cached = await deniedRepository.load();
      expect(cached.access, LibraryAccess.denied);
      expect(cached.documents.single.name, 'Guide.pdf');
      expect(cached.documents.single.isAvailable, isFalse);
      deniedRepository.dispose();
    },
  );

  test(
    'cold and warm content URIs are registered without source copies',
    () async {
      final cache = await Directory.systemTemp.createTemp('folio-uri-cache-');
      addTearDown(() async {
        if (await cache.exists()) {
          await cache.delete(recursive: true);
        }
      });
      final initial = _incoming(
        'content://provider/document/initial',
        'Initial.docx',
      );
      final gateway = _FakeStorageGateway(hasAccess: false, initial: initial);
      final repository = FileLibraryRepository(
        storageGateway: gateway,
        cacheDirectoryProvider: () async => cache,
        now: () => DateTime.utc(2026, 9, 13, 13),
      );

      await repository.load();
      final cold = await repository.consumeInitialDocument();
      expect(cold?.source.value, initial.value);
      expect(cold?.lastOpenedAt, isNotNull);

      final warmFuture = repository.incomingDocuments.first;
      await Future<void>.delayed(Duration.zero);
      final warm = _incoming('content://provider/document/warm', 'Warm.pptx');
      gateway.emit(warm);
      final registeredWarm = await warmFuture;
      expect(registeredWarm.source.value, warm.value);
      expect(registeredWarm.name, 'Warm.pptx');
      expect(await Directory('${cache.path}/session').exists(), isFalse);
      repository.dispose();
    },
  );

  test('permission request is delegated to Android settings', () async {
    final gateway = _FakeStorageGateway(hasAccess: false);
    final repository = FileLibraryRepository(storageGateway: gateway);

    await repository.requestFullAccess();

    expect(gateway.settingsRequests, 1);
    repository.dispose();
  });
}

IncomingDocument _incoming(String uri, String name) {
  return IncomingDocument(
    sourceType: 'uri',
    value: uri,
    displayName: name,
    sizeBytes: 120,
    modifiedAt: DateTime.utc(2026, 9, 13),
    mimeType: null,
    persistedPermission: true,
  );
}

class _FakeStorageGateway implements StorageGateway {
  _FakeStorageGateway({
    required this.hasAccess,
    this.roots = const <StorageRoot>[],
    this.initial,
  });

  bool hasAccess;
  final List<StorageRoot> roots;
  final IncomingDocument? initial;
  final StreamController<IncomingDocument> _incoming =
      StreamController<IncomingDocument>.broadcast();
  int settingsRequests = 0;

  void emit(IncomingDocument document) => _incoming.add(document);

  @override
  Future<IncomingDocument?> consumeInitialDocument() async => initial;

  @override
  Future<bool> hasAllFilesAccess() async => hasAccess;

  @override
  Stream<IncomingDocument> get incomingDocuments => _incoming.stream;

  @override
  Future<void> openAllFilesSettings() async {
    settingsRequests += 1;
  }

  @override
  Future<IncomingDocument?> requestDocumentAccess({
    required String displayName,
    String? mimeType,
  }) async => null;

  @override
  Future<List<StorageRoot>> storageRoots() async => roots;
}
