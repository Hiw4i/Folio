import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'document_entry.dart';

class DocumentScanBatch {
  const DocumentScanBatch({required this.documents, required this.isComplete});

  final List<DocumentEntry> documents;
  final bool isComplete;
}

abstract interface class DocumentScanner {
  Stream<DocumentScanBatch> scan(List<String> roots);
}

class IsolateDocumentScanner implements DocumentScanner {
  const IsolateDocumentScanner({this.batchSize = 64});

  final int batchSize;

  @override
  Stream<DocumentScanBatch> scan(List<String> roots) {
    ReceivePort? receivePort;
    Isolate? isolate;
    StreamSubscription<Object?>? messageSubscription;
    late final StreamController<DocumentScanBatch> controller;

    Future<void> close() async {
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
      await messageSubscription?.cancel();
      receivePort?.close();
      receivePort = null;
    }

    controller = StreamController<DocumentScanBatch>(
      onListen: () async {
        receivePort = ReceivePort();
        messageSubscription = receivePort!.listen((message) async {
          if (message is! Map) {
            return;
          }
          switch (message['type']) {
            case 'batch':
              final rawDocuments = message['documents'];
              if (rawDocuments is List) {
                controller.add(
                  DocumentScanBatch(
                    documents: <DocumentEntry>[
                      for (final raw in rawDocuments)
                        if (raw is Map)
                          DocumentEntry.fromJson(raw.cast<String, Object?>()),
                    ],
                    isComplete: false,
                  ),
                );
              }
            case 'error':
              controller.addError(
                FileSystemException(
                  message['message'] as String? ?? 'Document scan failed.',
                ),
              );
            case 'complete':
              controller.add(
                const DocumentScanBatch(
                  documents: <DocumentEntry>[],
                  isComplete: true,
                ),
              );
              isolate = null;
              receivePort?.close();
              receivePort = null;
              await controller.close();
          }
        });
        try {
          isolate = await Isolate.spawn<Map<String, Object?>>(
            _scanInIsolate,
            <String, Object?>{
              'port': receivePort!.sendPort,
              'roots': List<String>.of(roots),
              'batchSize': batchSize,
            },
            debugName: 'folio-document-scan',
          );
        } catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          await close();
          await controller.close();
        }
      },
      onCancel: close,
    );
    return controller.stream;
  }
}

Future<void> _scanInIsolate(Map<String, Object?> arguments) async {
  final port = arguments['port']! as SendPort;
  final roots = (arguments['roots']! as List).cast<String>();
  final batchSize = arguments['batchSize']! as int;
  final pending = <Map<String, Object?>>[];

  void emitBatch() {
    if (pending.isEmpty) {
      return;
    }
    port.send(<String, Object?>{
      'type': 'batch',
      'documents': List<Map<String, Object?>>.of(pending),
    });
    pending.clear();
  }

  try {
    final directories = <Directory>[for (final root in roots) Directory(root)];
    while (directories.isNotEmpty) {
      final directory = directories.removeLast();
      if (_isExcludedAndroidDirectory(directory.path)) {
        continue;
      }
      try {
        await for (final entity in directory.list(followLinks: false)) {
          final type = await FileSystemEntity.type(
            entity.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.directory) {
            if (!_isExcludedAndroidDirectory(entity.path)) {
              directories.add(Directory(entity.path));
            }
            continue;
          }
          if (type != FileSystemEntityType.file) {
            continue;
          }
          final name = _fileName(entity.path);
          final format = DocumentFormatPresentation.fromFileName(name);
          if (format == null) {
            continue;
          }
          try {
            final stat = await entity.stat();
            final source = FileDocumentSource(entity.path);
            pending.add(
              DocumentEntry(
                id: stableDocumentId(source),
                source: source,
                name: name,
                format: format,
                sizeBytes: stat.size,
                modifiedAt: stat.modified,
              ).toJson(),
            );
            if (pending.length >= batchSize) {
              emitBatch();
            }
          } on FileSystemException {
            // A file can disappear or become inaccessible during a scan.
          }
        }
      } on FileSystemException {
        // Android intentionally denies a few platform-owned directories.
      }
    }
    emitBatch();
  } catch (error) {
    port.send(<String, Object?>{'type': 'error', 'message': '$error'});
  } finally {
    port.send(<String, Object?>{'type': 'complete'});
  }
}

bool _isExcludedAndroidDirectory(String path) {
  final normalized = path.replaceAll('\\', '/').toLowerCase();
  return normalized.endsWith('/android/data') ||
      normalized.contains('/android/data/') ||
      normalized.endsWith('/android/obb') ||
      normalized.contains('/android/obb/');
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
