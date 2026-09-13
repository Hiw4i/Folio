import 'package:flutter/foundation.dart';

enum ReaderLoadState { loading, ready, failed }

enum ReaderFailureKind {
  unavailable,
  accessDenied,
  unsupportedEncoding,
  unsupportedFormat,
  unreadable,
}

@immutable
class ReaderFailure {
  const ReaderFailure({
    required this.kind,
    required this.title,
    required this.message,
    this.canRetry = false,
  });

  final ReaderFailureKind kind;
  final String title;
  final String message;
  final bool canRetry;
}

@immutable
class ReaderSearchHit {
  const ReaderSearchHit({
    required this.startOffset,
    required this.endOffset,
    required this.chunkIndex,
  });

  final int startOffset;
  final int endOffset;
  final int chunkIndex;
}
