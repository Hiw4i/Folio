import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../library/data/document_entry.dart';
import '../data/document_content_source.dart';
import '../data/text_document.dart';
import 'reader_state.dart';

abstract interface class DocumentRenderer implements Listenable {
  DocumentEntry get document;
  ReaderLoadState get loadState;
  ReaderFailure? get failure;
  String get query;
  bool get isSearching;
  int get hitCount;
  int get activeHitIndex;
  ReaderSearchHit? get activeHit;

  Future<void> open();
  Future<void> close();
  Future<void> search(String query);
  void showNextHit();
  void showPreviousHit();
  void dispose();
}

DocumentRenderer createDocumentRenderer({
  required DocumentEntry document,
  required DocumentContentSource contentSource,
}) {
  return switch (document.format) {
    DocumentFormat.pdf => PdfDocumentRenderer(
      document: document,
      contentSource: contentSource,
    ),
    DocumentFormat.txt || DocumentFormat.markdown => TextDocumentRenderer(
      document: document,
      loader: TextDocumentLoader(contentSource),
    ),
    _ => UnsupportedDocumentRenderer(document),
  };
}

class PdfDocumentRenderer extends ChangeNotifier implements DocumentRenderer {
  PdfDocumentRenderer({required this.document, required this.contentSource});

  static const int inMemoryDocumentThreshold = 1024 * 1024;

  @override
  final DocumentEntry document;
  final DocumentContentSource contentSource;

  @override
  ReaderLoadState loadState = ReaderLoadState.loading;
  @override
  ReaderFailure? failure;
  @override
  String query = '';
  @override
  bool isSearching = false;
  @override
  int activeHitIndex = -1;

  PreparedPdfSource? _preparedSource;
  PdfDocumentRef? _documentRef;
  PdfViewerController? _viewerController;
  PdfTextSearcher? _textSearcher;
  int _generation = 0;
  int _searchRevision = 0;
  int? _requestedHitIndex;
  bool _navigationRunning = false;
  bool _disposed = false;
  bool _probingText = false;

  int currentPage = 1;
  int pageCount = 0;
  bool? searchableTextAvailable;

  PdfDocumentRef? get documentRef => _documentRef;
  bool get sourceReady => _documentRef != null;

  String get positionLabel =>
      pageCount <= 0 ? 'PDF' : '$currentPage / $pageCount';

  bool get hasNoSearchableText =>
      query.trim().isNotEmpty &&
      !isSearching &&
      searchableTextAvailable == false;

  @override
  int get hitCount => _textSearcher?.matches.length ?? 0;

  @override
  ReaderSearchHit? get activeHit => null;

  @override
  Future<void> open() async {
    final generation = ++_generation;
    final previousSource = _preparedSource;
    _detachViewer();
    _preparedSource = null;
    _documentRef = null;
    loadState = ReaderLoadState.loading;
    failure = null;
    currentPage = 1;
    pageCount = 0;
    searchableTextAvailable = null;
    query = '';
    _searchRevision += 1;
    _requestedHitIndex = null;
    isSearching = false;
    activeHitIndex = -1;
    notifyListeners();
    if (previousSource != null) {
      await Future<void>.delayed(Duration.zero);
      await previousSource.close();
    }

    try {
      final prepared = await contentSource.preparePdf(document.source);
      if (_disposed || generation != _generation) {
        await prepared.close();
        return;
      }
      _preparedSource = prepared;
      _documentRef = _createDocumentRef(prepared);
      notifyListeners();
    } on DocumentReadException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _setReadFailure(error);
    } catch (_) {
      if (_disposed || generation != _generation) {
        return;
      }
      loadState = ReaderLoadState.failed;
      failure = const ReaderFailure(
        kind: ReaderFailureKind.unreadable,
        title: 'Could not open PDF',
        message: 'The PDF source could not be prepared safely.',
        canRetry: true,
      );
      notifyListeners();
    }
  }

  PdfDocumentRef _createDocumentRef(PreparedPdfSource prepared) {
    final key = PdfDocumentRefKey(document.id, <Object?>[
      document.modifiedAt.millisecondsSinceEpoch,
      prepared.length,
    ]);
    return switch (prepared) {
      PreparedPdfFile(:final path) => PdfDocumentRefFile(
        path,
        key: key,
        useProgressiveLoading: true,
      ),
      PreparedPdfData(:final bytes) => PdfDocumentRefData(
        bytes,
        sourceName: document.id,
        key: key,
        maxSizeToCacheOnMemory: inMemoryDocumentThreshold,
        useProgressiveLoading: true,
      ),
      PreparedPdfRandomAccess(:final length, :final readRange) =>
        PdfDocumentRefCustom(
          fileSize: length,
          sourceName: document.id,
          key: key,
          maxSizeToCacheOnMemory: inMemoryDocumentThreshold,
          useProgressiveLoading: true,
          read: (buffer, position, size) async {
            final bytes = await readRange(position, size);
            final count = bytes.length.clamp(0, size);
            buffer.setRange(0, count, bytes);
            return count;
          },
        ),
    };
  }

  void attachViewer(
    PdfDocument openedDocument,
    PdfViewerController controller,
  ) {
    if (_disposed || !identical(controller.documentRef, _documentRef)) {
      return;
    }
    _detachViewer();
    _viewerController = controller;
    _textSearcher = PdfTextSearcher(controller)..addListener(_searchChanged);
    pageCount = openedDocument.pages.length;
    currentPage = controller.pageNumber?.clamp(1, pageCount) ?? 1;
    loadState = ReaderLoadState.ready;
    failure = null;
    notifyListeners();
    if (query.trim().isNotEmpty) {
      _startTextSearch();
    }
  }

  void documentLoadFinished(PdfDocumentRef ref, bool succeeded) {
    if (_disposed || !identical(ref, _documentRef) || succeeded) {
      return;
    }
    final error = ref.resolveListenable().error;
    loadState = ReaderLoadState.failed;
    failure = error is PdfPasswordException
        ? const ReaderFailure(
            kind: ReaderFailureKind.passwordRequired,
            title: 'Password-protected PDF',
            message: 'Password entry is not included in Folio v1.',
          )
        : const ReaderFailure(
            kind: ReaderFailureKind.unreadable,
            title: 'Could not open PDF',
            message: 'The file is damaged or is not a valid PDF document.',
            canRetry: true,
          );
    notifyListeners();
  }

  void pageChanged(int? pageNumber) {
    if (pageNumber == null || pageNumber == currentPage || pageCount <= 0) {
      return;
    }
    currentPage = pageNumber.clamp(1, pageCount);
    notifyListeners();
  }

  void paintSearchMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
  }

  void _searchChanged() {
    final searcher = _textSearcher;
    if (_disposed || searcher == null) {
      return;
    }
    isSearching = searcher.isSearching;
    final currentIndex = searcher.currentIndex;
    activeHitIndex = currentIndex ?? activeHitIndex;
    int? firstHitToReveal;
    if (searcher.matches.isNotEmpty) {
      searchableTextAvailable = true;
      if (currentIndex == null && activeHitIndex < 0) {
        activeHitIndex = 0;
        firstHitToReveal = 0;
      }
    }
    notifyListeners();
    if (firstHitToReveal != null) {
      _requestPdfHit(firstHitToReveal, _searchRevision);
    }
    if (!searcher.isSearching &&
        query.trim().isNotEmpty &&
        searcher.matches.isEmpty &&
        searchableTextAvailable == null) {
      unawaited(_resolveTextAvailability(_generation));
    }
  }

  Future<void> _resolveTextAvailability(int generation) async {
    if (_probingText) {
      return;
    }
    final controller = _viewerController;
    final searcher = _textSearcher;
    if (controller == null || searcher == null || !controller.isReady) {
      return;
    }
    _probingText = true;
    try {
      final hasText = await controller.useDocument((pdf) async {
        for (final page in pdf.pages) {
          if (_disposed || generation != _generation) {
            return null;
          }
          final pageText = await searcher.loadText(pageNumber: page.pageNumber);
          if (pageText?.fullText.trim().isNotEmpty ?? false) {
            return true;
          }
        }
        return false;
      });
      if (!_disposed && generation == _generation && hasText != null) {
        searchableTextAvailable = hasText;
        notifyListeners();
      }
    } finally {
      _probingText = false;
    }
  }

  @override
  Future<void> search(String value) async {
    _searchRevision += 1;
    _requestedHitIndex = null;
    query = value;
    searchableTextAvailable = value.trim().isEmpty
        ? null
        : searchableTextAvailable;
    if (value.trim().isEmpty) {
      _textSearcher?.resetTextSearch();
      isSearching = false;
      activeHitIndex = -1;
      notifyListeners();
      return;
    }
    if (_textSearcher == null) {
      notifyListeners();
      return;
    }
    _startTextSearch();
  }

  void _startTextSearch() {
    isSearching = true;
    activeHitIndex = -1;
    _textSearcher!.startTextSearch(
      query.trim(),
      caseInsensitive: true,
      goToFirstMatch: false,
      searchImmediately: true,
    );
    notifyListeners();
  }

  @override
  void showNextHit() {
    final searcher = _textSearcher;
    if (searcher == null || searcher.matches.isEmpty) {
      return;
    }
    final current = activeHitIndex < 0 ? -1 : activeHitIndex;
    final next = (current + 1) % searcher.matches.length;
    _requestPdfHit(next, _searchRevision);
  }

  @override
  void showPreviousHit() {
    final searcher = _textSearcher;
    if (searcher == null || searcher.matches.isEmpty) {
      return;
    }
    final current = activeHitIndex < 0 ? 0 : activeHitIndex;
    final previous =
        (current - 1 + searcher.matches.length) % searcher.matches.length;
    _requestPdfHit(previous, _searchRevision);
  }

  void _requestPdfHit(int index, int searchRevision) {
    final searcher = _textSearcher;
    if (searcher == null ||
        index < 0 ||
        index >= searcher.matches.length ||
        searchRevision != _searchRevision) {
      return;
    }
    activeHitIndex = index;
    _requestedHitIndex = index;
    notifyListeners();
    if (!_navigationRunning) {
      unawaited(_drainPdfNavigation(searcher, searchRevision));
    }
  }

  Future<void> _drainPdfNavigation(
    PdfTextSearcher searcher,
    int searchRevision,
  ) async {
    _navigationRunning = true;
    while (!_disposed &&
        searchRevision == _searchRevision &&
        identical(searcher, _textSearcher)) {
      final index = _requestedHitIndex;
      _requestedHitIndex = null;
      if (index == null || index < 0 || index >= searcher.matches.length) {
        break;
      }
      try {
        await searcher.goToMatchOfIndex(index);
      } catch (_) {
        // A disposed viewer or superseded search can cancel ensureVisible.
      }
      if (_requestedHitIndex == null &&
          !_disposed &&
          searchRevision == _searchRevision &&
          identical(searcher, _textSearcher)) {
        final visiblePage = _viewerController?.pageNumber;
        if (visiblePage != null && pageCount > 0) {
          currentPage = visiblePage.clamp(1, pageCount);
        }
        notifyListeners();
      }
    }
    _navigationRunning = false;
    final currentSearcher = _textSearcher;
    if (_requestedHitIndex != null && !_disposed && currentSearcher != null) {
      unawaited(_drainPdfNavigation(currentSearcher, _searchRevision));
    }
  }

  void _cancelPdfNavigation() {
    _requestedHitIndex = null;
    if (!_navigationRunning) {
      return;
    }
    // The running ensureVisible call cannot be cancelled by pdfrx. Advancing
    // the search revision makes its completion inert.
    _searchRevision += 1;
  }

  void _setReadFailure(DocumentReadException error) {
    loadState = ReaderLoadState.failed;
    failure = switch (error.kind) {
      DocumentReadFailureKind.denied => const ReaderFailure(
        kind: ReaderFailureKind.accessDenied,
        title: 'Access expired',
        message: 'Folio no longer has permission to read this file.',
        canRetry: true,
      ),
      DocumentReadFailureKind.unavailable => const ReaderFailure(
        kind: ReaderFailureKind.unavailable,
        title: 'File unavailable',
        message: 'The file may have been moved, renamed or deleted.',
        canRetry: true,
      ),
      DocumentReadFailureKind.unreadable => ReaderFailure(
        kind: ReaderFailureKind.unreadable,
        title: 'Could not open PDF',
        message: error.message,
        canRetry: true,
      ),
    };
    notifyListeners();
  }

  void _detachViewer() {
    _cancelPdfNavigation();
    _viewerController = null;
    _textSearcher
      ?..removeListener(_searchChanged)
      ..dispose();
    _textSearcher = null;
    _probingText = false;
  }

  @override
  Future<void> close() async {
    _generation += 1;
    _detachViewer();
    _documentRef = null;
    final source = _preparedSource;
    _preparedSource = null;
    if (source != null) {
      await Future<void>.delayed(Duration.zero);
      await source.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    _detachViewer();
    final source = _preparedSource;
    _preparedSource = null;
    if (source != null) {
      unawaited(source.close());
    }
    super.dispose();
  }
}

class TextDocumentRenderer extends ChangeNotifier implements DocumentRenderer {
  TextDocumentRenderer({required this.document, required this.loader});

  @override
  final DocumentEntry document;
  final TextDocumentLoader loader;

  @override
  ReaderLoadState loadState = ReaderLoadState.loading;
  @override
  ReaderFailure? failure;
  TextDocument? content;
  List<ReaderSearchHit> _hits = const <ReaderSearchHit>[];
  @override
  String query = '';
  @override
  bool isSearching = false;
  @override
  int activeHitIndex = -1;
  int _generation = 0;
  bool _disposed = false;

  @override
  int get hitCount => _hits.length;

  List<ReaderSearchHit> get hits => _hits;

  @override
  ReaderSearchHit? get activeHit =>
      activeHitIndex < 0 || activeHitIndex >= _hits.length
      ? null
      : _hits[activeHitIndex];

  List<ReaderSearchHit> hitsForChunk(int chunkIndex) {
    return List<ReaderSearchHit>.unmodifiable(
      _hits.where((hit) => hit.chunkIndex == chunkIndex),
    );
  }

  @override
  Future<void> open() async {
    final generation = ++_generation;
    loadState = ReaderLoadState.loading;
    failure = null;
    content = null;
    _clearSearch(notify: false);
    notifyListeners();
    try {
      final loaded = await loader.load(document);
      if (_disposed || generation != _generation) {
        return;
      }
      content = loaded;
      loadState = ReaderLoadState.ready;
    } on UnsupportedTextEncodingException {
      if (_disposed || generation != _generation) {
        return;
      }
      loadState = ReaderLoadState.failed;
      failure = const ReaderFailure(
        kind: ReaderFailureKind.unsupportedEncoding,
        title: 'Unsupported text encoding',
        message: 'Folio can read UTF-8 and BOM-marked UTF-16 text files.',
      );
    } on DocumentReadException catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      loadState = ReaderLoadState.failed;
      failure = switch (error.kind) {
        DocumentReadFailureKind.denied => const ReaderFailure(
          kind: ReaderFailureKind.accessDenied,
          title: 'Access expired',
          message: 'Folio no longer has permission to read this file.',
          canRetry: true,
        ),
        DocumentReadFailureKind.unavailable => const ReaderFailure(
          kind: ReaderFailureKind.unavailable,
          title: 'File unavailable',
          message: 'The file may have been moved, renamed or deleted.',
          canRetry: true,
        ),
        DocumentReadFailureKind.unreadable => ReaderFailure(
          kind: ReaderFailureKind.unreadable,
          title: 'Could not open file',
          message: error.message,
          canRetry: true,
        ),
      };
    } catch (_) {
      if (_disposed || generation != _generation) {
        return;
      }
      loadState = ReaderLoadState.failed;
      failure = const ReaderFailure(
        kind: ReaderFailureKind.unreadable,
        title: 'Could not open file',
        message: 'The document could not be decoded safely.',
        canRetry: true,
      );
    }
    notifyListeners();
  }

  @override
  Future<void> search(String value) async {
    final normalized = value.trim();
    query = value;
    final loaded = content;
    final generation = ++_generation;
    if (normalized.isEmpty || loaded == null) {
      _hits = const <ReaderSearchHit>[];
      activeHitIndex = -1;
      isSearching = false;
      notifyListeners();
      return;
    }

    _hits = const <ReaderSearchHit>[];
    activeHitIndex = -1;
    isSearching = true;
    notifyListeners();
    final rawHits = await Isolate.run<List<List<int>>>(() {
      return _findSearchHits(
        loaded.text,
        normalized,
        loaded.isMarkdown,
        loaded.chunks.map((chunk) => chunk.startOffset).toList(),
      );
    });
    if (_disposed || generation != _generation) {
      return;
    }
    _hits = List<ReaderSearchHit>.unmodifiable(
      rawHits.map(
        (hit) => ReaderSearchHit(
          startOffset: hit[0],
          endOffset: hit[1],
          chunkIndex: hit[2],
        ),
      ),
    );
    activeHitIndex = _hits.isEmpty ? -1 : 0;
    isSearching = false;
    notifyListeners();
  }

  @override
  void showNextHit() {
    if (_hits.isEmpty) {
      return;
    }
    activeHitIndex = (activeHitIndex + 1) % _hits.length;
    notifyListeners();
  }

  @override
  void showPreviousHit() {
    if (_hits.isEmpty) {
      return;
    }
    activeHitIndex = (activeHitIndex - 1 + _hits.length) % _hits.length;
    notifyListeners();
  }

  void _clearSearch({required bool notify}) {
    query = '';
    isSearching = false;
    activeHitIndex = -1;
    _hits = const <ReaderSearchHit>[];
    if (notify) {
      notifyListeners();
    }
  }

  @override
  Future<void> close() async {
    _generation += 1;
    content = null;
    _clearSearch(notify: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}

class UnsupportedDocumentRenderer extends ChangeNotifier
    implements DocumentRenderer {
  UnsupportedDocumentRenderer(this.document);

  @override
  final DocumentEntry document;
  @override
  ReaderLoadState loadState = ReaderLoadState.loading;
  @override
  ReaderFailure? failure;
  @override
  String query = '';

  @override
  int get activeHitIndex => -1;
  @override
  ReaderSearchHit? get activeHit => null;
  @override
  int get hitCount => 0;
  @override
  bool get isSearching => false;

  @override
  Future<void> open() async {
    loadState = ReaderLoadState.failed;
    failure = ReaderFailure(
      kind: ReaderFailureKind.unsupportedFormat,
      title: '${document.format.extension.toUpperCase()} reader unavailable',
      message: 'This document renderer is not included in this build yet.',
    );
    notifyListeners();
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> search(String query) async {}
  @override
  void showNextHit() {}
  @override
  void showPreviousHit() {}
}

List<List<int>> _findSearchHits(
  String source,
  String query,
  bool markdown,
  List<int> chunkStarts,
) {
  final projected = markdown ? _markdownSearchProjection(source) : source;
  final searchable = projected.toLowerCase();
  final needle = query.toLowerCase();
  if (needle.isEmpty) {
    return const <List<int>>[];
  }
  final result = <List<int>>[];
  var offset = 0;
  while (offset <= searchable.length - needle.length) {
    final match = searchable.indexOf(needle, offset);
    if (match < 0) {
      break;
    }
    result.add(<int>[
      match,
      match + needle.length,
      _chunkIndexFor(match, chunkStarts),
    ]);
    offset = match + needle.length;
  }
  return result;
}

int _chunkIndexFor(int offset, List<int> starts) {
  var low = 0;
  var high = starts.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (starts[middle] <= offset) {
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return high.clamp(0, starts.length - 1);
}

String _markdownSearchProjection(String source) {
  final units = source.codeUnits.toList();

  void hide(int start, int end) {
    for (var index = start; index < end && index < units.length; index++) {
      if (units[index] != 0x0A && units[index] != 0x0D) {
        units[index] = 0x20;
      }
    }
  }

  for (final match in RegExp(
    r'!?\[([^\]]*)\]\(([^)]*)\)',
    multiLine: true,
  ).allMatches(source)) {
    final label = match.group(1) ?? '';
    final labelStart = source.indexOf(label, match.start);
    hide(match.start, labelStart);
    hide(labelStart + label.length, match.end);
  }
  for (final match in RegExp(
    r'^ {0,3}#{1,6}[ \t]+',
    multiLine: true,
  ).allMatches(source)) {
    hide(match.start, match.end);
  }
  for (final match in RegExp(r'[*_~`]').allMatches(source)) {
    hide(match.start, match.end);
  }
  return String.fromCharCodes(units);
}
