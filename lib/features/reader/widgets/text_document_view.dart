import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as markdown;

import '../../../shared/theme/folio_theme.dart';
import '../data/text_document.dart';
import '../logic/document_renderer.dart';
import '../logic/reader_state.dart';

const String _passiveStart = '\u{F0000}';
const String _passiveEnd = '\u{F0001}';
const String _activeStart = '\u{F0002}';
const String _activeEnd = '\u{F0003}';

class TextDocumentView extends StatelessWidget {
  const TextDocumentView({
    required this.renderer,
    required this.scrollController,
    required this.activeChunkKey,
    super.key,
  });

  final TextDocumentRenderer renderer;
  final ScrollController scrollController;
  final GlobalKey activeChunkKey;

  @override
  Widget build(BuildContext context) {
    final content = renderer.content!;
    if (content.chunks.isEmpty) {
      return const _EmptyDocument();
    }
    final activeChunk = renderer.activeHit?.chunkIndex;
    return FadingEdgeScrollView.fromScrollView(
      gradientFractionOnStart: 0.10,
      gradientFractionOnEnd: 0.12,
      child: ListView.builder(
        key: const ValueKey<String>('reader_content'),
        controller: scrollController,
        physics: const BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.viewPaddingOf(context).top + 104,
          24,
          MediaQuery.viewPaddingOf(context).bottom + 184,
        ),
        itemCount: content.chunks.length,
        itemBuilder: (context, index) {
          final chunk = content.chunks[index];
          final hits = renderer.hitsForChunk(index);
          return Center(
            key: index == activeChunk ? activeChunkKey : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: content.isMarkdown
                    ? _MarkdownChunk(
                        chunk: chunk,
                        hits: hits,
                        activeHit: renderer.activeHit,
                      )
                    : _PlainTextChunk(
                        chunk: chunk,
                        hits: hits,
                        activeHit: renderer.activeHit,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlainTextChunk extends StatelessWidget {
  const _PlainTextChunk({
    required this.chunk,
    required this.hits,
    required this.activeHit,
  });

  final TextDocumentChunk chunk;
  final List<ReaderSearchHit> hits;
  final ReaderSearchHit? activeHit;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      fontFamily: 'Inter',
      color: FolioColors.textPrimary,
      fontSize: 17,
      height: 1.62,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.05,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: _highlightedSpans(chunk, hits, activeHit, baseStyle),
      ),
      textAlign: TextAlign.start,
    );
  }
}

List<InlineSpan> _highlightedSpans(
  TextDocumentChunk chunk,
  List<ReaderSearchHit> hits,
  ReaderSearchHit? activeHit,
  TextStyle baseStyle,
) {
  if (hits.isEmpty) {
    return <InlineSpan>[TextSpan(text: chunk.text)];
  }
  final result = <InlineSpan>[];
  var cursor = 0;
  for (final hit in hits) {
    final start = (hit.startOffset - chunk.startOffset).clamp(
      cursor,
      chunk.text.length,
    );
    final end = (hit.endOffset - chunk.startOffset).clamp(
      start,
      chunk.text.length,
    );
    if (start > cursor) {
      result.add(TextSpan(text: chunk.text.substring(cursor, start)));
    }
    final active =
        identical(hit, activeHit) ||
        (activeHit?.startOffset == hit.startOffset &&
            activeHit?.endOffset == hit.endOffset);
    result.add(
      TextSpan(
        text: chunk.text.substring(start, end),
        style: baseStyle.copyWith(
          color: active ? const Color(0xFF17130A) : FolioColors.textPrimary,
          backgroundColor: active
              ? FolioColors.warmAccent
              : const Color(0x3DE7C768),
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    cursor = end;
  }
  if (cursor < chunk.text.length) {
    result.add(TextSpan(text: chunk.text.substring(cursor)));
  }
  return result;
}

class _MarkdownChunk extends StatelessWidget {
  const _MarkdownChunk({
    required this.chunk,
    required this.hits,
    required this.activeHit,
  });

  final TextDocumentChunk chunk;
  final List<ReaderSearchHit> hits;
  final ReaderSearchHit? activeHit;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data:
          '${chunk.renderPrefix}${_markedSource(chunk, hits, activeHit)}${chunk.renderSuffix}',
      selectable: false,
      softLineBreak: true,
      onTapLink: (text, href, title) {},
      imageBuilder: (uri, title, alt) => _BlockedImage(label: alt),
      inlineSyntaxes: <markdown.InlineSyntax>[
        _SearchHitSyntax(
          tag: 'folio-search-hit',
          start: _passiveStart,
          end: _passiveEnd,
        ),
        _SearchHitSyntax(
          tag: 'folio-search-hit-active',
          start: _activeStart,
          end: _activeEnd,
        ),
      ],
      builders: <String, MarkdownElementBuilder>{
        'folio-search-hit': _SearchHitBuilder(active: false),
        'folio-search-hit-active': _SearchHitBuilder(active: true),
      },
      styleSheet: _markdownStyleSheet(),
    );
  }
}

String _markedSource(
  TextDocumentChunk chunk,
  List<ReaderSearchHit> hits,
  ReaderSearchHit? activeHit,
) {
  if (hits.isEmpty) {
    return chunk.text;
  }
  var result = chunk.text;
  for (final hit in hits.reversed) {
    final start = (hit.startOffset - chunk.startOffset).clamp(0, result.length);
    final end = (hit.endOffset - chunk.startOffset).clamp(start, result.length);
    final active =
        activeHit?.startOffset == hit.startOffset &&
        activeHit?.endOffset == hit.endOffset;
    result = result.replaceRange(
      start,
      end,
      '${active ? _activeStart : _passiveStart}'
      '${result.substring(start, end)}'
      '${active ? _activeEnd : _passiveEnd}',
    );
  }
  return result;
}

class _SearchHitSyntax extends markdown.InlineSyntax {
  _SearchHitSyntax({
    required this.tag,
    required String start,
    required String end,
  }) : super('${RegExp.escape(start)}((?:.|\\n)*?)${RegExp.escape(end)}');

  final String tag;

  @override
  bool onMatch(markdown.InlineParser parser, Match match) {
    parser.addNode(markdown.Element.text(tag, match.group(1)!));
    return true;
  }
}

class _SearchHitBuilder extends MarkdownElementBuilder {
  _SearchHitBuilder({required this.active});

  final bool active;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    markdown.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? FolioColors.warmAccent : const Color(0x3DE7C768),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        element.textContent,
        style: (parentStyle ?? preferredStyle)?.copyWith(
          color: active ? const Color(0xFF17130A) : FolioColors.textPrimary,
          fontWeight: active ? FontWeight.w600 : null,
        ),
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyleSheet() {
  const body = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textPrimary,
    fontSize: 17,
    height: 1.58,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.05,
  );
  const heading = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textPrimary,
    fontWeight: FontWeight.w600,
    height: 1.18,
    letterSpacing: -0.4,
  );
  return MarkdownStyleSheet(
    p: body,
    a: body.copyWith(
      color: const Color(0xFFD8D6CF),
      decoration: TextDecoration.underline,
      decorationColor: FolioColors.textTertiary,
    ),
    h1: heading.copyWith(fontSize: 30),
    h2: heading.copyWith(fontSize: 25),
    h3: heading.copyWith(fontSize: 21),
    h4: heading.copyWith(fontSize: 18),
    h5: heading.copyWith(fontSize: 17),
    h6: heading.copyWith(fontSize: 16),
    em: body.copyWith(fontStyle: FontStyle.italic),
    strong: body.copyWith(fontWeight: FontWeight.w600),
    del: body.copyWith(decoration: TextDecoration.lineThrough),
    code: body.copyWith(
      fontFamily: 'monospace',
      fontSize: 15,
      color: const Color(0xFFE3E0D7),
      backgroundColor: const Color(0x14FFFFFF),
    ),
    blockquote: body.copyWith(color: FolioColors.textSecondary),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
    blockquoteDecoration: const BoxDecoration(
      color: Color(0x0AFFFFFF),
      border: Border(left: BorderSide(color: Color(0x52FFFFFF), width: 2)),
    ),
    codeblockPadding: const EdgeInsets.all(14),
    codeblockDecoration: BoxDecoration(
      color: const Color(0xA3131518),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0x18FFFFFF), width: 0.8),
    ),
    listBullet: body.copyWith(color: FolioColors.textSecondary),
    listIndent: 25,
    blockSpacing: 13,
    tableHead: body.copyWith(fontWeight: FontWeight.w600),
    tableBody: body.copyWith(fontSize: 15),
    tableBorder: TableBorder.all(color: const Color(0x24FFFFFF), width: 0.8),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Color(0x24FFFFFF), width: 0.8)),
    ),
  );
}

class _BlockedImage extends StatelessWidget {
  const _BlockedImage({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: label?.isNotEmpty == true ? label : 'Blocked document image',
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x18FFFFFF), width: 0.8),
        ),
        alignment: Alignment.center,
        child: Text(
          label?.isNotEmpty == true ? label! : 'External image blocked',
          textAlign: TextAlign.center,
          style: FolioText.metadata,
        ),
      ),
    );
  }
}

class _EmptyDocument extends StatelessWidget {
  const _EmptyDocument();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Empty document',
              style: TextStyle(
                fontFamily: 'Inter',
                color: FolioColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 7),
            Text(
              'There is no text to display.',
              textAlign: TextAlign.center,
              style: FolioText.metadata,
            ),
          ],
        ),
      ),
    );
  }
}
