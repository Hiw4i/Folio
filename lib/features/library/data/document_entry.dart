import 'package:flutter/foundation.dart';

enum DocumentFormat { pdf, docx, pptx, txt, markdown }

extension DocumentFormatPresentation on DocumentFormat {
  String get extension => switch (this) {
    DocumentFormat.pdf => 'pdf',
    DocumentFormat.docx => 'docx',
    DocumentFormat.pptx => 'pptx',
    DocumentFormat.txt => 'txt',
    DocumentFormat.markdown => 'md',
  };

  String get glyph => switch (this) {
    DocumentFormat.pdf => 'PDF',
    DocumentFormat.docx => 'W',
    DocumentFormat.pptx => 'P',
    DocumentFormat.txt => 'TXT',
    DocumentFormat.markdown => 'MD',
  };

  static DocumentFormat? fromFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return null;
    }
    return switch (name.substring(dot + 1).toLowerCase()) {
      'pdf' => DocumentFormat.pdf,
      'docx' => DocumentFormat.docx,
      'pptx' => DocumentFormat.pptx,
      'txt' => DocumentFormat.txt,
      'md' => DocumentFormat.markdown,
      _ => null,
    };
  }
}

sealed class DocumentSource {
  const DocumentSource();

  String get value;
}

@immutable
class FileDocumentSource extends DocumentSource {
  const FileDocumentSource(this.path);

  final String path;

  @override
  String get value => path;
}

@immutable
class UriDocumentSource extends DocumentSource {
  const UriDocumentSource(this.uri);

  final String uri;

  @override
  String get value => uri;
}

@immutable
class DocumentEntry {
  const DocumentEntry({
    required this.id,
    required this.source,
    required this.name,
    required this.format,
    required this.sizeBytes,
    required this.modifiedAt,
    this.lastOpenedAt,
    this.isAvailable = true,
  });

  final String id;
  final DocumentSource source;
  final String name;
  final DocumentFormat format;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime? lastOpenedAt;
  final bool isAvailable;

  DocumentEntry copyWith({DateTime? lastOpenedAt}) {
    return DocumentEntry(
      id: id,
      source: source,
      name: name,
      format: format,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      isAvailable: isAvailable,
    );
  }
}
