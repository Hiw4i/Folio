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
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'Must be positive');
    }
    ReceivePort? receivePort;
    Isolate? isolate;
    StreamSubscription<Object?>? messages;
    bool cancelled = false;
    bool finished = false;
    late final StreamController<DocumentScanBatch> controller;

    Future<void> cleanup() async {
      isolate?.kill(priority: Isolate.immediate);
      isolate = null;
      receivePort?.close();
      receivePort = null;
      final subscription = messages;
      messages = null;
      await subscription?.cancel();
    }

    void finish([Object? error, StackTrace? stack]) {
      if (cancelled || finished) {
        return;
      }
      finished = true;
      if (error != null) {
        controller.addError(error, stack);
      }
      unawaited(controller.close());
      unawaited(cleanup());
    }

    Future<void> start() async {
      final port = ReceivePort();
      receivePort = port;
      messages = port.listen((Object? message) {
        if (cancelled || finished) {
          return;
        }
        if (message == null) {
          finish(StateError('Document scan isolate exited before completion.'));
          return;
        }
        if (message is List) {
          finish(StateError('Document scan isolate failed: ${message.first}'));
          return;
        }
        if (message is! Map) {
          return;
        }
        try {
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
              finish(
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
              finish();
          }
        } catch (error, stack) {
          finish(error, stack);
        }
      });
      try {
        final worker = await Isolate.spawn<Map<String, Object?>>(
          _scanInIsolate,
          <String, Object?>{
            'port': port.sendPort,
            'roots': List<String>.of(roots),
            'batchSize': batchSize,
          },
          onError: port.sendPort,
          onExit: port.sendPort,
          errorsAreFatal: true,
          debugName: 'folio-document-scan',
        );
        // Cancellation can happen while spawn is still awaiting its handle.
        if (cancelled || finished) {
          worker.kill(priority: Isolate.immediate);
        } else {
          isolate = worker;
        }
      } catch (error, stack) {
        finish(error, stack);
      }
    }

    controller = StreamController<DocumentScanBatch>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        cancelled = true;
        await cleanup();
      },
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
    final visited = <String>{};
    while (directories.isNotEmpty) {
      final directory = directories.removeLast();
      final normalizedPath = directory.absolute.uri
          .normalizePath()
          .toFilePath();
      if (!visited.add(normalizedPath) ||
          _isExcludedAndroidDirectory(directory.path)) {
        continue;
      }
      try {
        await for (final entity in directory.list(followLinks: false)) {
          // Directory.list already reports entity types. Avoid an additional
          // filesystem call for every file, directory and unsupported asset.
          if (entity is Directory) {
            if (!_isExcludedAndroidDirectory(entity.path)) {
              directories.add(Directory(entity.path));
            }
            continue;
          }
          if (entity is! File) {
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
                // dart:io has no birthtime. On Windows `changed` is the
                // creation time; on POSIX it is ctime (best effort fallback).
                createdAt: stat.changed,
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
