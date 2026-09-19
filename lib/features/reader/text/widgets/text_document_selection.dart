import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionAreaState;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../shared/selection/folio_selection_toolbar.dart';
import '../data/text_document.dart';
import '../logic/markdown_selection_text.dart';

/// One selection owner for the entire lazy reader, not one editor per paragraph.
/// Full-document Copy reads the source only on explicit user action; it never
/// forces every off-screen chunk to build just to implement Select all.
class TextDocumentSelection extends StatefulWidget {
  const TextDocumentSelection({
    required this.document,
    required this.child,
    this.onSelectionChanged,
    super.key,
  });

  final TextDocument document;
  final Widget child;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  State<TextDocumentSelection> createState() => _TextDocumentSelectionState();
}

class _TextDocumentSelectionState extends State<TextDocumentSelection> {
  final _areaKey = GlobalKey<SelectionAreaState>();
  final _delegate = _DocumentSelectionDelegate();
  bool _copying = false;
  bool _hasSelection = false;
  String? _cachedMarkdownText;

  @override
  void didUpdateWidget(TextDocumentSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.document, oldWidget.document)) {
      _cachedMarkdownText = null;
      _delegate.invalidate();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _areaKey.currentState?.selectableRegion.clearSelection();
        }
      });
    }
  }

  void _selectionChanged(SelectedContent? content) {
    final active = content?.plainText.isNotEmpty ?? false;
    if (_hasSelection == active) {
      return;
    }
    _hasSelection = active;
    widget.onSelectionChanged?.call(active);
  }

  Future<void> _copy(SelectableRegionState region) async {
    if (_copying || (!_hasSelection && !_delegate.selectsDocument)) {
      return;
    }
    if (!_delegate.selectsDocument) {
      for (final item in region.contextMenuButtonItems) {
        if (item.type == ContextMenuButtonType.copy) {
          item.onPressed?.call();
          return;
        }
      }
      return;
    }
    _copying = true;
    final document = widget.document;
    final revision = _delegate.revision;
    try {
      var text = document.text;
      if (document.isMarkdown) {
        // Rendering an entire long Markdown file synchronously on a tap would
        // trade the old selection bug for a UI stall. Parse off-thread instead.
        text = _cachedMarkdownText ?? (text.length > 65536
            ? await compute(markdownSelectionText, text)
            : markdownSelectionText(text));
        if (mounted && identical(widget.document, document)) {
          _cachedMarkdownText = text;
        }
      }
      if (!mounted ||
          !identical(widget.document, document) ||
          revision != _delegate.revision) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted && identical(widget.document, document) &&
          revision == _delegate.revision) {
        region.hideToolbar();
        region.clearSelection();
      }
    } catch (error) {
      // Do not discard the user's selection on a failed clipboard operation.
      debugPrint('Folio text copy failed: $error');
    } finally {
      _copying = false;
    }
  }

  Widget _menu(BuildContext context, SelectableRegionState region) {
    return FolioSelectionToolbar(
      anchors: region.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () => unawaited(_copy(region)),
        ),
        if (!_delegate.selectsDocument)
          ContextMenuButtonItem(
            type: ContextMenuButtonType.selectAll,
            onPressed: () => region.selectAll(SelectionChangedCause.toolbar),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        // SelectableRegion's overridable keyboard action must copy the full
        // document too, rather than just the currently materialized children.
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (intent) {
            final region = _areaKey.currentState?.selectableRegion;
            if (region != null) {
              unawaited(_copy(region));
            }
            return null;
          },
        ),
      },
      child: SelectionArea(
        key: _areaKey,
        contextMenuBuilder: _menu,
        onSelectionChanged: _selectionChanged,
        child: SelectionContainer(
          delegate: _delegate,
          child: widget.child,
        ),
      ),
    );
  }
}

/// This container has one stable child: Scrollable's own selection delegate.
/// The Scrollable still handles lazy child registration and edge auto-scroll.
/// Track actual selection commands, not geometry notifications, so scrolling
/// and orientation changes cannot turn Select all into Copy visible text only.
class _DocumentSelectionDelegate extends StaticSelectionContainerDelegate {
  bool selectsDocument = false;
  int revision = 0;

  void invalidate() {
    selectsDocument = false;
    revision++;
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    selectsDocument = event.type == SelectionEventType.selectAll;
    revision++;
    return super.dispatchSelectionEvent(event);
  }
}
