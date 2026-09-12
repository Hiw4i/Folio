import 'document_entry.dart';

enum LibraryAccess { granted, denied }

class LibrarySnapshot {
  const LibrarySnapshot({required this.documents, required this.access});

  final List<DocumentEntry> documents;
  final LibraryAccess access;
}

abstract interface class LibraryRepository {
  Future<LibrarySnapshot> load();

  Future<DocumentEntry> markOpened(DocumentEntry document);
}
