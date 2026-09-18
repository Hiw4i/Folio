import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/data/document_entry.dart';
import '../data/document_content_source.dart';
import 'document_renderer.dart';
import 'renderer_lifecycle.dart';

/// One speculative renderer at most. Rapid touches while scrolling cannot
/// retain a growing collection of PDFs/Office sessions until their TTL expires.
abstract final class ReaderPreloader {
  static _PrimedReader? _primed;
  static const Duration timeToLive = Duration(seconds: 15);

  static String _key(DocumentEntry document) =>
      '${document.id}::${document.source.value}::${document.format.index}'
      '::${document.modifiedAt.microsecondsSinceEpoch}::${document.sizeBytes}';

  static void prime({
    required DocumentEntry document,
    required DocumentContentSource contentSource,
  }) {
    if (!document.isAvailable) {
      return;
    }
    final key = _key(document);
    final current = _primed;
    if (current != null &&
        current.key == key &&
        identical(current.contentSource, contentSource)) {
      return;
    }
    clear();
    final renderer = createDocumentRenderer(
      document: document,
      contentSource: contentSource,
    );
    final entry = _PrimedReader(key, contentSource, renderer);
    _primed = entry;
    entry.eviction = Timer(timeToLive, () {
      if (identical(_primed, entry)) {
        clear();
      }
    });
    unawaited(
      renderer.open().catchError((Object error, StackTrace stack) {
        debugPrint('Folio speculative reader preparation failed: $error');
        if (identical(_primed, entry)) {
          clear();
        }
      }),
    );
  }

  static DocumentRenderer? adopt(
    DocumentEntry document, {
    DocumentContentSource? contentSource,
  }) {
    final entry = _primed;
    if (entry == null || entry.key != _key(document)) {
      return null;
    }
    if (contentSource != null &&
        !identical(entry.contentSource, contentSource)) {
      clear();
      return null;
    }
    _primed = null;
    entry.eviction?.cancel();
    return entry.renderer;
  }

  /// Releases unadopted work on memory pressure or when leaving the library.
  static void clear() {
    final entry = _primed;
    _primed = null;
    if (entry == null) {
      return;
    }
    entry.eviction?.cancel();
    releaseDocumentRenderer(entry.renderer);
  }

  @visibleForTesting
  static int get pendingCount => _primed == null ? 0 : 1;

  @visibleForTesting
  static void resetForTest() => clear();
}

class _PrimedReader {
  _PrimedReader(this.key, this.contentSource, this.renderer);

  final String key;
  final DocumentContentSource contentSource;
  final DocumentRenderer renderer;
  Timer? eviction;
}
