import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter/services.dart' show MethodChannel, PlatformException;

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

  /// Prepares a PDF without forcing a whole filesystem document into Dart
  /// memory. Android content URIs use bounded random-access reads when the
  /// provider is seekable and a session-scoped cache file otherwise.
  Future<PreparedPdfSource> preparePdf(DocumentSource source);
}

sealed class PreparedPdfSource {
  const PreparedPdfSource({required this.length});

  final int length;

  Future<void> close();
}

class PreparedPdfFile extends PreparedPdfSource {
  const PreparedPdfFile({
    required this.path,
    required super.length,
    this.onClose,
  });

  final String path;
  final Future<void> Function()? onClose;

  @override
  Future<void> close() async {
    final closer = onClose;
    if (closer != null) {
      await closer();
    }
  }
}

class PreparedPdfData extends PreparedPdfSource {
  PreparedPdfData({required this.bytes}) : super(length: bytes.length);

  final Uint8List bytes;

  @override
  Future<void> close() async {}
}

class PreparedPdfRandomAccess extends PreparedPdfSource {
  const PreparedPdfRandomAccess({
    required super.length,
    required this.readRange,
    required this.onClose,
  });

  final Future<Uint8List> Function(int position, int size) readRange;
  final Future<void> Function() onClose;

  @override
  Future<void> close() => onClose();
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

  @override
  Future<PreparedPdfSource> preparePdf(DocumentSource source) async {
    if (source case FileDocumentSource(:final path)) {
      try {
        final file = File(path);
        final length = await file.length();
        return PreparedPdfFile(path: path, length: length);
      } on FileSystemException catch (error) {
        throw DocumentReadException(
          error.osError?.errorCode == 13
              ? DocumentReadFailureKind.denied
              : DocumentReadFailureKind.unavailable,
          'The PDF file could not be opened.',
        );
      }
    }

    final uri = (source as UriDocumentSource).uri;
    try {
      final raw = await _methodChannel.invokeMapMethod<String, Object?>(
        'preparePdfSource',
        <String, Object?>{'uri': uri},
      );
      final rawSessionId = raw?['sessionId'];
      final sessionId = rawSessionId is String && rawSessionId.isNotEmpty
          ? rawSessionId
          : null;
      Future<void>? closing;
      Future<void> closeSession() {
        if (sessionId == null) {
          return Future<void>.value();
        }
        return closing ??= _methodChannel.invokeMethod<void>(
          'closePdfSource',
          <String, Object?>{'sessionId': sessionId},
        );
      }

      try {
        final kind = raw?['kind'];
        final rawLength = raw?['length'];
        final length = rawLength is num && rawLength.isFinite
            ? rawLength.toInt()
            : null;
        if (kind is! String ||
            length == null ||
            length <= 0 ||
            sessionId == null) {
          throw const DocumentReadException(
            DocumentReadFailureKind.unreadable,
            'The document provider returned an invalid PDF source.',
          );
        }
        if (kind == 'file') {
          final path = raw?['path'];
          if (path is! String || path.isEmpty) {
            throw const DocumentReadException(
              DocumentReadFailureKind.unreadable,
              'The PDF cache file could not be prepared.',
            );
          }
          return PreparedPdfFile(
            path: path,
            length: length,
            onClose: closeSession,
          );
        }
        if (kind == 'range') {
          return PreparedPdfRandomAccess(
            length: length,
            readRange: (position, size) {
              if (closing != null) {
                throw const DocumentReadException(
                  DocumentReadFailureKind.unavailable,
                  'The PDF source has been closed.',
                );
              }
              if (position < 0 || size < 0 || position > length) {
                throw RangeError('Invalid PDF range: $position + $size');
              }
              if (size == 0 || position == length) {
                return Future<Uint8List>.value(Uint8List(0));
              }
              return _readPdfRange(
                sessionId: sessionId,
                position: position,
                size: size.clamp(0, length - position),
              );
            },
            onClose: closeSession,
          );
        }
        throw const DocumentReadException(
          DocumentReadFailureKind.unreadable,
          'The document provider returned an unsupported PDF source.',
        );
      } catch (_) {
        // A provider can allocate a session but return malformed metadata.
        // Always release that session without masking the original failure.
        try {
          await closeSession();
        } catch (error) {
          debugPrint('Folio invalid PDF session cleanup failed: $error');
        }
        rethrow;
      }
    } on PlatformException catch (error) {
      final kind = switch (error.code) {
        'access_denied' => DocumentReadFailureKind.denied,
        'not_found' => DocumentReadFailureKind.unavailable,
        _ => DocumentReadFailureKind.unreadable,
      };
      throw DocumentReadException(
        kind,
        error.message ?? 'The document provider could not prepare this PDF.',
      );
    }
  }

  Future<Uint8List> _readPdfRange({
    required String sessionId,
    required int position,
    required int size,
  }) async {
    try {
      final bytes = await _methodChannel.invokeMethod<Uint8List>(
        'readPdfRange',
        <String, Object?>{
          'sessionId': sessionId,
          'position': position,
          'size': size,
        },
      );
      if (bytes == null) {
        throw const DocumentReadException(
          DocumentReadFailureKind.unreadable,
          'The PDF source returned no data.',
        );
      }
      if (bytes.length > size) {
        return Uint8List.sublistView(bytes, 0, size);
      }
      return bytes;
    } on PlatformException catch (error) {
      throw DocumentReadException(
        error.code == 'not_found'
            ? DocumentReadFailureKind.unavailable
            : DocumentReadFailureKind.unreadable,
        error.message ?? 'The PDF source could not be read.',
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

  @override
  Future<PreparedPdfSource> preparePdf(DocumentSource source) async {
    final bytes = await read(source);
    return PreparedPdfData(bytes: bytes);
  }
}
