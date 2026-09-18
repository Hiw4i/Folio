import 'dart:async';

import 'package:flutter/foundation.dart';

import 'document_renderer_contract.dart';

/// Invalidate the renderer immediately while observing asynchronous native
/// cleanup. A route disposal must not produce an unhandled platform error.
void releaseDocumentRenderer(DocumentRenderer renderer) {
  final closing = Future<void>.sync(renderer.close);
  renderer.dispose();
  unawaited(
    closing.catchError((Object error, StackTrace stack) {
      debugPrint('Folio renderer cleanup failed: $error');
    }),
  );
}

/// Best-effort native cleanup shared by PDF/Office reloads and disposal.
/// A failed close must not prevent a replacement document from opening.
Future<void> closeReaderResource(Future<void> Function() close) async {
  try {
    await close();
  } catch (error) {
    debugPrint('Folio native resource cleanup failed: $error');
  }
}
