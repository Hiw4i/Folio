import 'dart:async';

import 'package:flutter/cupertino.dart'
    show
        cupertinoDesktopTextSelectionHandleControls,
        cupertinoTextSelectionHandleControls;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show
        Theme,
        TextMagnifier,
        desktopTextSelectionHandleControls,
        materialTextSelectionHandleControls;
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
  final _regionKey = GlobalKey<SelectableRegionState>();
  final _focusNode = FocusNode(debugLabel: 'Document selection');
  final Set<int> _touchPointers = <int>{};
  final _delegate = _DocumentSelectionDelegate();
  bool _copying = false;
  bool _hasSelection = false;
  String? _cachedMarkdownText;

  @override
  void didUpdateWidget(TextDocumentSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.document, oldWidget.document)) {
      _cachedMarkdownText = null;
      _touchPointers.clear();
      _delegate.invalidate();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _regionKey.currentState?.clearSelection();
        }
      });
    }
  }

  void _pointerDown(PointerDownEvent event) {
    // Mouse drags must remain native range-selection gestures. Touch/stylus
    // cancellation, on the other hand, usually means a scroll won the arena.
    if (event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _touchPointers.add(event.pointer);
    }
  }

  void _pointerFinished(PointerEvent event) {
    // Render-object Listeners run before the gesture arena processes up/cancel.
    // Keep the guard through that dispatch, not just until our Listener sees up.
    // Native taps/long presses still dispatch edge/word events normally.
    scheduleMicrotask(() {
      if (mounted) _touchPointers.remove(event.pointer);
    });
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
        _touchPointers.clear();
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
    _focusNode.dispose();
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
            final region = _regionKey.currentState;
            if (region != null) {
              unawaited(_copy(region));
            }
            return null;
          },
        ),
      },
      // The same platform controls and magnifier as SelectionArea. Override
      // only cancellation at the region boundary, BEFORE Flutter clears its
      // root delegate/handle owners; filtering in a child delegate is too late.
      child: _ScrollPreservingSelectionRegion(
        key: _regionKey,
        preserveGestureSelection: () =>
            _touchPointers.isNotEmpty && _focusNode.hasFocus,
        selectionControls: switch (Theme.of(context).platform) {
          TargetPlatform.android || TargetPlatform.fuchsia =>
            materialTextSelectionHandleControls,
          TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
          TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
          TargetPlatform.linux || TargetPlatform.windows =>
            desktopTextSelectionHandleControls,
        },
        magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
        focusNode: _focusNode,
        contextMenuBuilder: _menu,
        onSelectionChanged: _selectionChanged,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _pointerDown,
          onPointerUp: _pointerFinished,
          onPointerCancel: _pointerFinished,
          child: SelectionContainer(
            delegate: _delegate,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Uses Flutter's selection engine, with one targeted cancellation policy.
/// A native tap collapses through edge events, and long press selects a word;
/// neither is blocked. Real focus loss must still clear the selection.
class _ScrollPreservingSelectionRegion extends SelectableRegion {
  const _ScrollPreservingSelectionRegion({
    required this.preserveGestureSelection,
    required super.selectionControls,
    required super.child,
    super.focusNode,
    super.contextMenuBuilder,
    super.magnifierConfiguration,
    super.onSelectionChanged,
    super.key,
  });

  final bool Function() preserveGestureSelection;

  @override
  SelectableRegionState createState() => _ScrollPreservingSelectionRegionState();
}

class _ScrollPreservingSelectionRegionState extends SelectableRegionState {
  @override
  void clearSelection() {
    final region = widget as _ScrollPreservingSelectionRegion;
    if (!region.preserveGestureSelection()) {
      super.clearSelection();
    }
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
