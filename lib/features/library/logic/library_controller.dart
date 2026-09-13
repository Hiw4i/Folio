import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/document_entry.dart';
import '../data/library_repository.dart';

enum LibraryFilter { all, pdf, word, powerPoint, text }

extension LibraryFilterPresentation on LibraryFilter {
  String get label => switch (this) {
    LibraryFilter.all => 'All',
    LibraryFilter.pdf => 'PDF',
    LibraryFilter.word => 'Word',
    LibraryFilter.powerPoint => 'PPTX',
    LibraryFilter.text => 'Text',
  };

  bool accepts(DocumentFormat format) => switch (this) {
    LibraryFilter.all => true,
    LibraryFilter.pdf => format == DocumentFormat.pdf,
    LibraryFilter.word => format == DocumentFormat.docx,
    LibraryFilter.powerPoint => format == DocumentFormat.pptx,
    LibraryFilter.text =>
      format == DocumentFormat.txt || format == DocumentFormat.markdown,
  };
}

enum LibraryLoadState { loading, ready, failed }

class LibraryController extends ChangeNotifier {
  LibraryController({required this.repository});

  final LibraryRepository repository;
  List<DocumentEntry> _documents = const <DocumentEntry>[];
  LibraryLoadState _loadState = LibraryLoadState.loading;
  LibraryAccess _access = LibraryAccess.granted;
  LibraryFilter _filter = LibraryFilter.all;
  String _query = '';
  bool _disposed = false;
  bool _isRefreshing = false;
  bool _refreshFailed = false;
  DocumentEntry? _pendingDocument;
  DocumentEntry? _unavailableDocument;
  StreamSubscription<LibrarySnapshot>? _refreshSubscription;
  Completer<void>? _refreshCompleter;
  StreamSubscription<DocumentEntry>? _incomingSubscription;
  int _refreshGeneration = 0;

  LibraryLoadState get loadState => _loadState;
  LibraryAccess get access => _access;
  LibraryFilter get filter => _filter;
  String get query => _query;
  int get totalCount => _documents.length;
  bool get isRefreshing => _isRefreshing;
  bool get refreshFailed => _refreshFailed;
  DocumentEntry? get pendingDocument => _pendingDocument;
  DocumentEntry? get unavailableDocument => _unavailableDocument;

  List<DocumentEntry> get matches {
    final normalizedQuery = _query.trim().toLowerCase();
    final result = _documents.where((document) {
      return _filter.accepts(document.format) &&
          (normalizedQuery.isEmpty ||
              document.name.toLowerCase().contains(normalizedQuery));
    }).toList();
    result.sort(_byName);
    return List<DocumentEntry>.unmodifiable(result);
  }

  List<DocumentEntry> get recentDocuments {
    if (_filter != LibraryFilter.all || _query.trim().isNotEmpty) {
      return const <DocumentEntry>[];
    }
    final result =
        _documents.where((document) => document.lastOpenedAt != null).toList()
          ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return List<DocumentEntry>.unmodifiable(result.take(10));
  }

  List<DocumentEntry> get regularDocuments {
    final recentIds = recentDocuments.map((document) => document.id).toSet();
    return List<DocumentEntry>.unmodifiable(
      matches.where((document) => !recentIds.contains(document.id)),
    );
  }

  Future<void> load() async {
    _loadState = LibraryLoadState.loading;
    notifyListeners();
    try {
      final snapshot = await repository.load();
      if (_disposed) {
        return;
      }
      _documents = snapshot.documents;
      _access = snapshot.access;
      _loadState = LibraryLoadState.ready;
      _listenForIncomingDocuments();
      final initialDocument = await repository.consumeInitialDocument();
      if (initialDocument != null && !_disposed) {
        _upsert(initialDocument);
        _pendingDocument = initialDocument;
      }
    } catch (_) {
      if (_disposed) {
        return;
      }
      _loadState = LibraryLoadState.failed;
    }
    notifyListeners();
    if (_loadState == LibraryLoadState.ready) {
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    await _refreshSubscription?.cancel();
    if (_refreshCompleter case final previous? when !previous.isCompleted) {
      previous.complete();
    }
    _isRefreshing = true;
    _refreshFailed = false;
    final generation = ++_refreshGeneration;
    notifyListeners();
    final completed = Completer<void>();
    _refreshCompleter = completed;
    _refreshSubscription = repository.refresh().listen(
      (snapshot) {
        if (_disposed || generation != _refreshGeneration) {
          return;
        }
        _documents = snapshot.documents;
        _access = snapshot.access;
        notifyListeners();
      },
      onError: (Object _) {
        if (!_disposed && generation == _refreshGeneration) {
          _refreshFailed = true;
        }
      },
      onDone: () {
        if (!_disposed && generation == _refreshGeneration) {
          _isRefreshing = false;
          notifyListeners();
        }
        if (!completed.isCompleted) {
          completed.complete();
        }
      },
      cancelOnError: false,
    );
    await completed.future;
  }

  Future<void> requestFullAccess() => repository.requestFullAccess();

  void selectFilter(LibraryFilter value) {
    if (_filter == value) {
      return;
    }
    _filter = value;
    notifyListeners();
  }

  void updateQuery(String value) {
    if (_query == value) {
      return;
    }
    _query = value;
    notifyListeners();
  }

  Future<void> open(DocumentEntry document) async {
    if (!document.isAvailable) {
      _unavailableDocument = document;
      notifyListeners();
      return;
    }
    final updated = await repository.markOpened(document);
    if (_disposed) {
      return;
    }
    _upsert(updated);
    _pendingDocument = updated;
    notifyListeners();
  }

  DocumentEntry? takePendingDocument() {
    final pending = _pendingDocument;
    _pendingDocument = null;
    return pending;
  }

  void dismissUnavailable() {
    if (_unavailableDocument == null) {
      return;
    }
    _unavailableDocument = null;
    notifyListeners();
  }

  Future<void> recoverUnavailable() async {
    final document = _unavailableDocument;
    if (document == null) {
      return;
    }
    final recovered = await repository.recoverAccess(document);
    if (_disposed) {
      return;
    }
    if (recovered != null) {
      _documents = _documents.where((item) => item.id != document.id).toList();
      _upsert(recovered);
      _pendingDocument = recovered;
    }
    _unavailableDocument = null;
    notifyListeners();
  }

  Future<void> removeUnavailableFromRecents() async {
    final document = _unavailableDocument;
    if (document == null) {
      return;
    }
    await repository.removeFromRecents(document);
    if (_disposed) {
      return;
    }
    _documents = _documents.where((item) => item.id != document.id).toList();
    _unavailableDocument = null;
    notifyListeners();
  }

  Future<void> removeFromRecents(DocumentEntry document) async {
    await repository.removeFromRecents(document);
    if (_disposed) {
      return;
    }
    if (document.source is UriDocumentSource || !document.isAvailable) {
      _documents = _documents.where((item) => item.id != document.id).toList();
    } else {
      _documents = <DocumentEntry>[
        for (final item in _documents)
          if (item.id == document.id)
            item.copyWith(lastOpenedAt: null)
          else
            item,
      ];
    }
    notifyListeners();
  }

  void _listenForIncomingDocuments() {
    _incomingSubscription ??= repository.incomingDocuments.listen((document) {
      if (_disposed) {
        return;
      }
      _upsert(document);
      _pendingDocument = document;
      notifyListeners();
    });
  }

  void _upsert(DocumentEntry document) {
    final index = _documents.indexWhere((item) => item.id == document.id);
    if (index < 0) {
      _documents = <DocumentEntry>[..._documents, document];
    } else {
      _documents = <DocumentEntry>[
        for (var i = 0; i < _documents.length; i++)
          if (i == index) document else _documents[i],
      ];
    }
  }

  static int _byName(DocumentEntry a, DocumentEntry b) {
    final insensitive = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return insensitive != 0 ? insensitive : a.name.compareTo(b.name);
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshGeneration += 1;
    unawaited(_refreshSubscription?.cancel());
    unawaited(_incomingSubscription?.cancel());
    if (_refreshCompleter case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    repository.dispose();
    super.dispose();
  }
}
