import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../library/data/document_entry.dart';
import '../../data/document_content_source.dart';

enum TextDocumentEncoding { utf8, utf16LittleEndian, utf16BigEndian }

extension TextDocumentEncodingLabel on TextDocumentEncoding {
  String get label => switch (this) {
    TextDocumentEncoding.utf8 => 'UTF-8',
    TextDocumentEncoding.utf16LittleEndian => 'UTF-16 LE',
    TextDocumentEncoding.utf16BigEndian => 'UTF-16 BE',
  };
}

class UnsupportedTextEncodingException implements Exception {
  const UnsupportedTextEncodingException();

  @override
  String toString() => 'The file is not valid UTF-8 or BOM-marked UTF-16.';
}

class TextDocumentChunk {
  const TextDocumentChunk({
    required this.startOffset,
    required this.text,
    this.renderPrefix = '',
    this.renderSuffix = '',
  });

  final int startOffset;
  final String text;
  final String renderPrefix;
  final String renderSuffix;

  int get endOffset => startOffset + text.length;
}

class TextDocument {
  const TextDocument({
    required this.text,
    required this.chunks,
    required this.encoding,
    required this.isMarkdown,
  });

  final String text;
  final List<TextDocumentChunk> chunks;
  final TextDocumentEncoding encoding;
  final bool isMarkdown;
}

class TextDocumentLoader {
  const TextDocumentLoader(this.source);

  final DocumentContentSource source;

  Future<TextDocument> load(DocumentEntry document) async {
    final bytes = await source.read(document.source);
    final transferable = TransferableTypedData.fromList(<Uint8List>[bytes]);
    final payload = await Isolate.run<Map<String, Object?>>(
      () => _decodeAndChunk(
        transferable.materialize().asUint8List(),
        document.format == DocumentFormat.markdown,
      ),
    );
    final rawChunks = payload['chunks']! as List<Object?>;
    return TextDocument(
      text: payload['text']! as String,
      encoding: TextDocumentEncoding.values[payload['encoding']! as int],
      isMarkdown: payload['markdown']! as bool,
      chunks: List<TextDocumentChunk>.unmodifiable(
        rawChunks.map((raw) {
          final chunk = (raw! as Map<Object?, Object?>).cast<String, Object?>();
          return TextDocumentChunk(
            startOffset: chunk['start']! as int,
            text: chunk['text']! as String,
            renderPrefix: chunk['prefix']! as String,
            renderSuffix: chunk['suffix']! as String,
          );
        }),
      ),
    );
  }
}

Map<String, Object?> _decodeAndChunk(Uint8List bytes, bool markdown) {
  final decoded = _decodeStrict(bytes);
  return <String, Object?>{
    'text': decoded.$1,
    'encoding': decoded.$2.index,
    'markdown': markdown,
    'chunks': _chunkText(decoded.$1, markdown),
  };
}

(String, TextDocumentEncoding) _decodeStrict(Uint8List bytes) {
  try {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return (
        _decodeUtf16(bytes, start: 2, littleEndian: true),
        TextDocumentEncoding.utf16LittleEndian,
      );
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return (
        _decodeUtf16(bytes, start: 2, littleEndian: false),
        TextDocumentEncoding.utf16BigEndian,
      );
    }
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    return (
      const Utf8Decoder(allowMalformed: false).convert(bytes, start),
      TextDocumentEncoding.utf8,
    );
  } on FormatException {
    throw const UnsupportedTextEncodingException();
  }
}

String _decodeUtf16(
  Uint8List bytes, {
  required int start,
  required bool littleEndian,
}) {
  if ((bytes.length - start).isOdd) {
    throw const FormatException('Odd UTF-16 byte count.');
  }
  final codePoints = <int>[];
  int codeUnitAt(int index) => littleEndian
      ? bytes[index] | bytes[index + 1] << 8
      : bytes[index] << 8 | bytes[index + 1];

  for (var index = start; index < bytes.length; index += 2) {
    final unit = codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (index + 3 >= bytes.length) {
        throw const FormatException('Incomplete UTF-16 surrogate pair.');
      }
      final low = codeUnitAt(index + 2);
      if (low < 0xDC00 || low > 0xDFFF) {
        throw const FormatException('Invalid UTF-16 surrogate pair.');
      }
      codePoints.add(0x10000 + ((unit - 0xD800) << 10) + low - 0xDC00);
      index += 2;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      throw const FormatException('Unexpected UTF-16 low surrogate.');
    } else {
      codePoints.add(unit);
    }
  }
  return String.fromCharCodes(codePoints);
}

List<Object?> _chunkText(String text, bool markdown) {
  if (text.isEmpty) {
    return const <Object?>[];
  }
  const targetLength = 6000;
  const maximumLength = 10000;
  final chunks = <Object?>[];
  var start = 0;
  var cursor = 0;
  var inFence = false;
  var fenceMarker = '```';
  var fenceHeader = '```';

  void addChunk(int end, {String prefix = '', String suffix = ''}) {
    if (end <= start) {
      return;
    }
    chunks.add(<String, Object?>{
      'start': start,
      'text': text.substring(start, end),
      'prefix': prefix,
      'suffix': suffix,
    });
    start = end;
  }

  var carriedPrefix = '';
  while (cursor < text.length) {
    var lineEnd = text.indexOf('\n', cursor);
    lineEnd = lineEnd < 0 ? text.length : lineEnd + 1;
    final line = text.substring(cursor, lineEnd).trimLeft();
    final fence =
        markdown && (line.startsWith('```') || line.startsWith('~~~'));
    if (fence) {
      final marker = line.startsWith('```') ? '```' : '~~~';
      if (!inFence) {
        inFence = true;
        fenceMarker = marker;
        fenceHeader = line.trimRight();
      } else if (line.startsWith(fenceMarker)) {
        inFence = false;
      }
    }

    final length = lineEnd - start;
    final blankBoundary = line.trim().isEmpty;
    if (length >= targetLength && (!markdown || (!inFence && blankBoundary))) {
      addChunk(lineEnd, prefix: carriedPrefix);
      carriedPrefix = '';
    } else if (length >= maximumLength) {
      if (markdown && inFence) {
        addChunk(lineEnd, prefix: carriedPrefix, suffix: '\n$fenceMarker\n');
        carriedPrefix = '$fenceHeader\n';
      } else {
        addChunk(lineEnd, prefix: carriedPrefix);
        carriedPrefix = '';
      }
    }
    cursor = lineEnd;
  }
  addChunk(text.length, prefix: carriedPrefix);
  return chunks;
}
