import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../library/data/document_entry.dart';
import '../data/document_content_source.dart';
import 'document_renderer.dart';

/// Starts document preparation on tap-down, while the [OpenContainer]
/// morph animation is still running, so the reader route can adopt an
/// already-warming renderer instead of starting I/O after the transition.
///
/// Only the tapped document is ever primed (no neighbour prefetch): the
/// entry is evicted shortly after if the reader never adopts it.
abstract final class ReaderPreloader {
  static final Map<String, DocumentRenderer> _primed =
      <String, DocumentRenderer>{};
  static final Map<String, Timer> _eviction = <String, Timer>{};

  static const Duration timeToLive = Duration(seconds: 15);

  static String _key(DocumentEntry document) =>
      '${document.id}::${document.modifiedAt.microsecondsSinceEpoch}';

  static void prime({
    required DocumentEntry document,
    required DocumentContentSource contentSource,
  }) {
    if (!document.isAvailable) {
      return;
    }
    final key = _key(document);
    if (_primed.containsKey(key)) {
      return;
    }
    final renderer = createDocumentRenderer(
      document: document,
      contentSource: contentSource,
    );
    _primed[key] = renderer;
    _eviction[key]?.cancel();
    _eviction[key] = Timer(timeToLive, () {
      final expired = _primed.remove(key);
      _eviction.remove(key);
      if (expired != null) {
        unawaited(expired.close());
        expired.dispose();
      }
    });
    unawaited(renderer.open());
  }

  /// Takes the warming renderer for [document], or `null` when nothing was
  /// primed (e.g. opened from an intent or the prime already expired).
  static DocumentRenderer? adopt(DocumentEntry document) {
    final renderer = _primed.remove(_key(document));
    _eviction.remove(_key(document))?.cancel();
    return renderer;
  }

  @visibleForTesting
  static void resetForTest() {
    for (final timer in _eviction.values) {
      timer.cancel();
    }
    _eviction.clear();
    for (final renderer in _primed.values) {
      unawaited(renderer.close());
      renderer.dispose();
    }
    _primed.clear();
  }
}
