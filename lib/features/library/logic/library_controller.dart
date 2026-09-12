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

  LibraryLoadState get loadState => _loadState;
  LibraryAccess get access => _access;
  LibraryFilter get filter => _filter;
  String get query => _query;
  int get totalCount => _documents.length;

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
    } catch (_) {
      if (_disposed) {
        return;
      }
      _loadState = LibraryLoadState.failed;
    }
    notifyListeners();
  }

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
    final updated = await repository.markOpened(document);
    if (_disposed) {
      return;
    }
    _documents = <DocumentEntry>[
      for (final item in _documents)
        if (item.id == updated.id) updated else item,
    ];
    notifyListeners();
  }

  static int _byName(DocumentEntry a, DocumentEntry b) {
    final insensitive = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return insensitive != 0 ? insensitive : a.name.compareTo(b.name);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
