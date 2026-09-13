import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/glass/glass_panel.dart';
import '../../../shared/glass/liquid_glass_button.dart';
import '../../../shared/glass/liquid_glass_control.dart';
import '../../../shared/glass/liquid_morphing_control.dart';
import '../../../shared/glass/liquid_search_control.dart';
import '../../../shared/theme/folio_theme.dart';
import '../../library/data/document_entry.dart';
import '../data/document_content_source.dart';
import '../logic/document_renderer.dart';
import '../logic/reader_state.dart';
import 'text_document_view.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.document,
    required this.contentSource,
    required this.onRemoveFromRecents,
    super.key,
  });

  final DocumentEntry document;
  final DocumentContentSource contentSource;
  final Future<void> Function() onRemoveFromRecents;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<LiquidSearchControlState> _searchKey =
      GlobalKey<LiquidSearchControlState>();
  final GlobalKey<LiquidMorphingControlState> _menuKey =
      GlobalKey<LiquidMorphingControlState>();
  GlobalKey _activeChunkKey = GlobalKey();
  late final DocumentRenderer _renderer;
  Timer? _searchDebounce;
  Timer? _revealTimer;
  bool _chromeVisible = true;
  bool _searchExpanded = false;
  bool _menuOpen = false;
  bool _infoOpen = false;
  int _lastActiveHit = -2;
  int _progressPercent = 0;

  @override
  void initState() {
    super.initState();
    _renderer = createDocumentRenderer(
      document: widget.document,
      contentSource: widget.contentSource,
    )..addListener(_rendererChanged);
    _scrollController.addListener(_scrollChanged);
    unawaited(_renderer.open());
  }

  void _rendererChanged() {
    if (!mounted || _lastActiveHit == _renderer.activeHitIndex) {
      return;
    }
    _lastActiveHit = _renderer.activeHitIndex;
    _activeChunkKey = GlobalKey();
    if (_renderer.activeHit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealActiveHit());
    }
  }

  void _scrollChanged() {
    if (!_scrollController.hasClients) {
      return;
    }
    final extent = _scrollController.position.maxScrollExtent;
    final next = extent <= 0
        ? 0
        : (_scrollController.offset / extent * 100).round().clamp(0, 100);
    if (next != _progressPercent && mounted) {
      setState(() => _progressPercent = next);
    }
  }

  void _revealActiveHit() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final renderer = _renderer;
    if (renderer is! TextDocumentRenderer || renderer.activeHit == null) {
      return;
    }
    final content = renderer.content;
    if (content == null || content.chunks.isEmpty) {
      return;
    }
    final chunkIndex = renderer.activeHit!.chunkIndex;
    final target =
        _scrollController.position.maxScrollExtent *
        (chunkIndex / content.chunks.length);
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    unawaited(
      _scrollController.animateTo(
        target.clamp(0, _scrollController.position.maxScrollExtent),
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      ),
    );
    _revealTimer?.cancel();
    _revealTimer = Timer(
      reducedMotion ? Duration.zero : const Duration(milliseconds: 300),
      () {
        final targetContext = _activeChunkKey.currentContext;
        if (mounted && targetContext != null && targetContext.mounted) {
          Scrollable.ensureVisible(
            targetContext,
            alignment: 0.28,
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      },
    );
  }

  void _searchChanged(String query) {
    _searchDebounce?.cancel();
    setState(() => _chromeVisible = true);
    if (query.trim().isEmpty) {
      unawaited(_renderer.search(''));
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 160),
      () => unawaited(_renderer.search(query)),
    );
  }

  void _handleBackButton() {
    if (_infoOpen) {
      setState(() => _infoOpen = false);
      return;
    }
    if (_menuOpen) {
      _menuKey.currentState?.close();
      return;
    }
    if (_searchKey.currentState?.handleBack() ?? false) {
      return;
    }
    Navigator.of(context).maybePop();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (_searchExpanded) {
      return false;
    }
    if (notification case ScrollUpdateNotification(:final scrollDelta)) {
      if ((scrollDelta ?? 0) > 0 &&
          notification.metrics.pixels > 24 &&
          _chromeVisible) {
        setState(() => _chromeVisible = false);
      } else if ((scrollDelta ?? 0) < 0 && !_chromeVisible) {
        setState(() => _chromeVisible = true);
      }
    } else if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward &&
        !_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    return false;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _revealTimer?.cancel();
    _renderer
      ..removeListener(_rendererChanged)
      ..close()
      ..dispose();
    _scrollController
      ..removeListener(_scrollChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final reducedMotion = media.disableAnimations;
    final chromeDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 230);
    final showChrome = _chromeVisible || _searchExpanded;
    return PopScope<void>(
      canPop: !_menuOpen && !_infoOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && (_menuOpen || _infoOpen)) {
          if (_infoOpen) {
            setState(() => _infoOpen = false);
          } else {
            _menuKey.currentState?.close();
          }
        }
      },
      child: ColoredBox(
        key: const ValueKey<String>('reader_surface'),
        color: FolioColors.background,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const _ReaderBackground(),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (!_chromeVisible) {
                  setState(() => _chromeVisible = true);
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: AnimatedBuilder(
                  animation: _renderer,
                  builder: (context, child) => _ReaderBody(
                    renderer: _renderer,
                    scrollController: _scrollController,
                    activeChunkKey: _activeChunkKey,
                  ),
                ),
              ),
            ),
            _AnimatedChrome(
              key: const ValueKey<String>('reader_top_chrome'),
              visible: showChrome,
              duration: chromeDuration,
              hiddenOffset: const Offset(0, -1.25),
              child: _TopChrome(
                document: widget.document,
                onBack: _handleBackButton,
              ),
            ),
            _AnimatedChrome(
              visible: showChrome,
              duration: chromeDuration,
              hiddenOffset: const Offset(0, 1.4),
              child: AnimatedBuilder(
                animation: _renderer,
                builder: (context, child) {
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Positioned(
                        left: 20,
                        bottom:
                            media.viewInsets.bottom +
                            media.viewPadding.bottom +
                            28,
                        child: _ProgressPill(
                          label: _renderer is TextDocumentRenderer
                              ? '$_progressPercent%'
                              : widget.document.format.extension.toUpperCase(),
                        ),
                      ),
                      if (_renderer.query.trim().isNotEmpty)
                        Positioned(
                          right: 20,
                          bottom:
                              media.viewInsets.bottom +
                              media.viewPadding.bottom +
                              102,
                          child: _SearchNavigator(renderer: _renderer),
                        ),
                    ],
                  );
                },
              ),
            ),
            _AnimatedChrome(
              visible: showChrome,
              duration: chromeDuration,
              hiddenOffset: const Offset(0, 1.0),
              child: Positioned(
                left: 0,
                right: 0,
                bottom: media.viewInsets.bottom,
                height:
                    LiquidSearchControlState.height + media.viewPadding.bottom,
                child: LiquidSearchControl(
                  key: _searchKey,
                  hintText: 'Search in document',
                  semanticsLabel: 'Search in document',
                  onChanged: _searchChanged,
                  onSubmitted: (_) {
                    if (_renderer.hitCount > 0) {
                      _renderer.showNextHit();
                    }
                  },
                  onExpansionChanged: (expanded) {
                    if (mounted && _searchExpanded != expanded) {
                      setState(() {
                        _searchExpanded = expanded;
                        _chromeVisible = true;
                      });
                    }
                  },
                ),
              ),
            ),
            _AnimatedChrome(
              visible: showChrome || _menuOpen,
              duration: chromeDuration,
              hiddenOffset: const Offset(0, -1.25),
              child: LiquidMorphingControl(
                key: _menuKey,
                collapsedHitKey: const ValueKey<String>('reader_menu_button'),
                collapsedSemanticsLabel: 'Document menu',
                expandedSemanticsLabel: 'Document menu',
                geometryBuilder: (viewport) {
                  final top = media.viewPadding.top + 10;
                  return LiquidMorphGeometry(
                    collapsedRect: Rect.fromLTWH(
                      viewport.width - 64,
                      top,
                      48,
                      48,
                    ),
                    expandedRect: Rect.fromLTWH(
                      viewport.width - 242,
                      top,
                      226,
                      112,
                    ),
                    expandedCornerRadius: 24,
                  );
                },
                collapsedChild: const Center(
                  child: Text(
                    '•••',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: FolioColors.textPrimary,
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                expandedChild: _ReaderMenuContent(
                  onFileInfo: () {
                    _menuKey.currentState?.close();
                    setState(() => _infoOpen = true);
                  },
                  onRemove: () {
                    _menuKey.currentState?.close();
                    unawaited(widget.onRemoveFromRecents());
                  },
                ),
                onExpansionChanged: (expanded) {
                  if (mounted && _menuOpen != expanded) {
                    setState(() {
                      _menuOpen = expanded;
                      _chromeVisible = true;
                    });
                  }
                },
              ),
            ),
            if (_infoOpen)
              _FileInfoOverlay(
                document: widget.document,
                onDismiss: () => setState(() => _infoOpen = false),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.renderer,
    required this.scrollController,
    required this.activeChunkKey,
  });

  final DocumentRenderer renderer;
  final ScrollController scrollController;
  final GlobalKey activeChunkKey;

  @override
  Widget build(BuildContext context) {
    return switch (renderer.loadState) {
      ReaderLoadState.loading => const _ReaderStatus(
        title: 'Opening document',
        message: 'Preparing text for reading…',
        loading: true,
      ),
      ReaderLoadState.failed => _ReaderFailureView(
        failure: renderer.failure!,
        onRetry: renderer.open,
      ),
      ReaderLoadState.ready when renderer is TextDocumentRenderer =>
        TextDocumentView(
          renderer: renderer as TextDocumentRenderer,
          scrollController: scrollController,
          activeChunkKey: activeChunkKey,
        ),
      ReaderLoadState.ready => const _ReaderStatus(
        title: 'Nothing to display',
        message: 'This document has no readable content.',
      ),
    };
  }
}

class _AnimatedChrome extends StatelessWidget {
  const _AnimatedChrome({
    required this.visible,
    required this.duration,
    required this.hiddenOffset,
    required this.child,
    super.key,
  });

  final bool visible;
  final Duration duration;
  final Offset hiddenOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : hiddenOffset,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Stack(fit: StackFit.expand, children: <Widget>[child]),
        ),
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({required this.document, required this.onBack});

  final DocumentEntry document;
  final VoidCallback onBack;

  static const TextStyle _titleStyle = TextStyle(
    fontFamily: 'Inter',
    color: FolioColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
  );

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.viewPaddingOf(context).top + 10,
      height: 50,
      child: Row(
        children: <Widget>[
          _LiquidIconButton(
            key: const ValueKey<String>('reader_back_button'),
            semanticsLabel: 'Back',
            symbol: '‹',
            symbolSize: 32,
            onTap: onBack,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textPainter =
                    TextPainter(
                      text: TextSpan(text: document.name, style: _titleStyle),
                      maxLines: 1,
                      ellipsis: '…',
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout(
                      maxWidth: (constraints.maxWidth - 36).clamp(
                        0.0,
                        double.infinity,
                      ),
                    );
                final titleWidth = (textPainter.width + 36).clamp(
                  76.0,
                  constraints.maxWidth,
                );
                return Align(
                  child: _LiquidChromeObject(
                    key: const ValueKey<String>('reader_title_glass'),
                    size: Size(titleWidth, 42),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        child: Text(
                          document.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: _titleStyle,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          const SizedBox(width: 48, height: 48),
        ],
      ),
    );
  }
}

class _LiquidIconButton extends StatelessWidget {
  const _LiquidIconButton({
    required this.semanticsLabel,
    required this.symbol,
    required this.onTap,
    this.symbolSize = 18,
    super.key,
  });

  final String semanticsLabel;
  final String symbol;
  final VoidCallback onTap;
  final double symbolSize;

  @override
  Widget build(BuildContext context) {
    return _LiquidChromeObject(
      size: const Size(48, 48),
      semanticsLabel: semanticsLabel,
      onTap: onTap,
      child: Text(
        symbol,
        style: TextStyle(
          fontFamily: 'Inter',
          color: FolioColors.textPrimary,
          fontSize: symbolSize,
          height: 1,
          fontWeight: FontWeight.w500,
          letterSpacing: symbol == '•••' ? 1.2 : 0,
        ),
      ),
    );
  }
}

class _LiquidChromeObject extends StatelessWidget {
  const _LiquidChromeObject({
    required this.size,
    required this.child,
    this.semanticsLabel,
    this.onTap,
    super.key,
  });

  final Size size;
  final Widget child;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      child: OverflowBox(
        minWidth: size.width + 80,
        maxWidth: size.width + 80,
        minHeight: size.height + 80,
        maxHeight: size.height + 80,
        child: LiquidGlassControl(
          semanticsLabel: semanticsLabel,
          size: size,
          hitSlop: 0,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _LiquidChromeObject(
      key: const ValueKey<String>('reader_progress_glass'),
      size: const Size(62, 38),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            color: FolioColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _SearchNavigator extends StatelessWidget {
  const _SearchNavigator({required this.renderer});

  final DocumentRenderer renderer;

  @override
  Widget build(BuildContext context) {
    final label = renderer.isSearching
        ? 'Searching…'
        : renderer.hitCount == 0
        ? 'No matches'
        : '${renderer.activeHitIndex + 1} of ${renderer.hitCount}';
    return GlassPanel(
      borderRadius: 23,
      padding: const EdgeInsets.only(left: 15, right: 4),
      child: SizedBox(
        height: 46,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              key: const ValueKey<String>('reader_search_count'),
              style: const TextStyle(
                fontFamily: 'Inter',
                color: FolioColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            _SearchStepButton(
              key: const ValueKey<String>('reader_previous_hit'),
              label: 'Previous match',
              symbol: '↑',
              enabled: renderer.hitCount > 0,
              onTap: renderer.showPreviousHit,
            ),
            _SearchStepButton(
              key: const ValueKey<String>('reader_next_hit'),
              label: 'Next match',
              symbol: '↓',
              enabled: renderer.hitCount > 0,
              onTap: renderer.showNextHit,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchStepButton extends StatelessWidget {
  const _SearchStepButton({
    required this.label,
    required this.symbol,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final String symbol;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 40,
          height: 46,
          child: Center(
            child: Text(
              symbol,
              style: TextStyle(
                fontFamily: 'Inter',
                color: enabled
                    ? FolioColors.textPrimary
                    : FolioColors.textTertiary,
                fontSize: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderMenuContent extends StatelessWidget {
  const _ReaderMenuContent({required this.onFileInfo, required this.onRemove});

  final VoidCallback onFileInfo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MenuAction(label: 'File info', onTap: onFileInfo),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 0.8,
              child: ColoredBox(color: FolioColors.separator),
            ),
          ),
          _MenuAction(label: 'Remove from Recents', onTap: onRemove),
        ],
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17),
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  color: FolioColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileInfoOverlay extends StatelessWidget {
  const _FileInfoOverlay({required this.document, required this.onDismiss});

  final DocumentEntry document;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'File info',
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: const ColoredBox(color: Color(0xA6000000)),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GlassPanel(
                    borderRadius: 28,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'File info',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: FolioColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _InfoRow(label: 'Name', value: document.name),
                        _InfoRow(
                          label: 'Format',
                          value: document.format.extension.toUpperCase(),
                        ),
                        _InfoRow(
                          label: 'Size',
                          value: _formatFileSize(document.sizeBytes),
                        ),
                        _InfoRow(
                          label: 'Modified',
                          value: _formatDate(document.modifiedAt),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: LiquidGlassButton(
                            label: 'Done',
                            width: 108,
                            height: 48,
                            onTap: onDismiss,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 78, child: Text(label, style: FolioText.metadata)),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: FolioColors.textPrimary,
                fontSize: 12.5,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderFailureView extends StatelessWidget {
  const _ReaderFailureView({required this.failure, required this.onRetry});

  final ReaderFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _ReaderStatus(
      title: failure.title,
      message: failure.message,
      action: failure.canRetry
          ? LiquidGlassButton(
              label: 'Try again',
              width: 132,
              height: 50,
              onTap: () => unawaited(onRetry()),
            )
          : null,
    );
  }
}

class _ReaderStatus extends StatelessWidget {
  const _ReaderStatus({
    required this.title,
    required this.message,
    this.loading = false,
    this.action,
  });

  final String title;
  final String message;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 70, 34, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading) ...<Widget>[
              const _LoadingGlyph(),
              const SizedBox(height: 18),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: FolioColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FolioText.metadata,
            ),
            if (action != null) ...<Widget>[const SizedBox(height: 2), action!],
          ],
        ),
      ),
    );
  }
}

class _LoadingGlyph extends StatelessWidget {
  const _LoadingGlyph();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: const SizedBox(
        width: 34,
        height: 6,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            _LoadingDot(opacity: 0.35),
            _LoadingDot(opacity: 0.62),
            _LoadingDot(opacity: 0.92),
          ],
        ),
      ),
    );
  }
}

class _LoadingDot extends StatelessWidget {
  const _LoadingDot({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: FolioColors.textPrimary.withValues(alpha: opacity),
      ),
    );
  }
}

class _ReaderBackground extends StatelessWidget {
  const _ReaderBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF121315),
            FolioColors.background,
            Color(0xFF08090A),
          ],
          stops: <double>[0, 0.34, 1],
        ),
      ),
    );
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}
