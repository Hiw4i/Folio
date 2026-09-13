import 'dart:io';

import 'package:flutter/services.dart';

import '../../library/data/document_entry.dart';

enum DocumentReadFailureKind { unavailable, denied, unreadable }

class DocumentReadException implements Exception {
  const DocumentReadException(this.kind, this.message);

  final DocumentReadFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

abstract interface class DocumentContentSource {
  Future<Uint8List> read(DocumentSource source);
}

class DeviceDocumentContentSource implements DocumentContentSource {
  const DeviceDocumentContentSource({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel('folio/storage');

  final MethodChannel _methodChannel;

  @override
  Future<Uint8List> read(DocumentSource source) async {
    try {
      final result = switch (source) {
        FileDocumentSource(:final path) => File(path).readAsBytes(),
        UriDocumentSource(:final uri) => _readContentUri(uri),
      };
      return await result;
    } on FileSystemException catch (error) {
      throw DocumentReadException(
        error.osError?.errorCode == 13
            ? DocumentReadFailureKind.denied
            : DocumentReadFailureKind.unavailable,
        'The file could not be read.',
      );
    }
  }

  Future<Uint8List> _readContentUri(String uri) async {
    try {
      final bytes = await _methodChannel.invokeMethod<Uint8List>(
        'readContentUri',
        <String, Object?>{'uri': uri},
      );
      if (bytes == null) {
        throw const DocumentReadException(
          DocumentReadFailureKind.unavailable,
          'The document provider returned no data.',
        );
      }
      return bytes;
    } on PlatformException catch (error) {
      final kind = switch (error.code) {
        'access_denied' => DocumentReadFailureKind.denied,
        'not_found' => DocumentReadFailureKind.unavailable,
        _ => DocumentReadFailureKind.unreadable,
      };
      throw DocumentReadException(
        kind,
        error.message ?? 'The document provider could not read this file.',
      );
    }
  }
}

class MemoryDocumentContentSource implements DocumentContentSource {
  MemoryDocumentContentSource(this.documents);

  final Map<String, Uint8List> documents;

  @override
  Future<Uint8List> read(DocumentSource source) async {
    final bytes = documents[source.value];
    if (bytes == null) {
      throw const DocumentReadException(
        DocumentReadFailureKind.unavailable,
        'The test document is unavailable.',
      );
    }
    return Uint8List.fromList(bytes);
  }
}
