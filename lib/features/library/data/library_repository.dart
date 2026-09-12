import 'document_entry.dart';

enum LibraryAccess { granted, denied }

class LibrarySnapshot {
  const LibrarySnapshot({required this.documents, required this.access});

  final List<DocumentEntry> documents;
  final LibraryAccess access;
}

abstract interface class LibraryRepository {
  Future<LibrarySnapshot> load();

  Stream<LibrarySnapshot> refresh();

  Future<void> requestFullAccess();

  Stream<DocumentEntry> get incomingDocuments;

  Future<DocumentEntry?> consumeInitialDocument();

  Future<DocumentEntry> markOpened(DocumentEntry document);

  Future<DocumentEntry?> recoverAccess(DocumentEntry document);

  Future<void> removeFromRecents(DocumentEntry document);

  void dispose();
}
