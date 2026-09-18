import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../shared/glass/liquid_glass.dart';
import '../../../shared/theme/folio_theme.dart';
import '../../../shared/widgets/scroll_edge_fade.dart';
import '../../reader/data/document_content_source.dart';
import '../../reader/logic/reader_preloader.dart';
import '../../reader/widgets/reader_screen.dart';
import '../../settings/widgets/folio_settings_sheet.dart';
import '../data/document_entry.dart';
import '../data/library_repository.dart';
import '../logic/library_controller.dart';
import 'document_row.dart';
import 'library_background.dart';
import 'library_filter_bar.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.controller,
    required this.documentContentSource,
    super.key,
  });

  final LibraryController controller;
  final DocumentContentSource documentContentSource;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  bool _readerOpen = false;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_openPendingDocument);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.controller.load());
      }
    });
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_openPendingDocument);
      widget.controller.addListener(_openPendingDocument);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(widget.controller.load());
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_openPendingDocument);
    _scrollController.dispose();
    ReaderPreloader.clear();
    super.dispose();
  }

  void _openPendingDocument() {
    if (!mounted || _readerOpen || _settingsOpen) {
      return;
    }
    final document = widget.controller.takePendingDocument();
    if (document == null) {
      return;
    }
    _readerOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _readerOpen = false;
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          pageBuilder: (context, animation, secondaryAnimation) => ReaderScreen(
            document: document,
            contentSource: widget.documentContentSource,
            onRemoveFromRecents: () =>
                widget.controller.removeFromRecents(document),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
      if (!mounted) {
        return;
      }
      _readerOpen = false;
      _openPendingDocument();
    });
  }

  bool _beginReaderOpen() {
    if (!mounted || _readerOpen || _settingsOpen) {
      return false;
    }
    _readerOpen = true;
    return true;
  }

  void _readerClosed() {
    if (!mounted) {
      return;
    }
    _readerOpen = false;
    _openPendingDocument();
  }

  Future<void> _openSettings() async {
    if (_settingsOpen || _readerOpen) {
      return;
    }
    _settingsOpen = true;
    try {
      await showFolioSettingsSheet(context);
    } finally {
      _settingsOpen = false;
      if (mounted) {
        _openPendingDocument();
      }
    }
  }

  @override
  void didHaveMemoryPressure() {
    ReaderPreloader.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ReaderPreloader.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      child: Positioned(
        left: 0,
        right: 0,
        bottom: media.viewInsets.bottom,
        height: LiquidSearchControlState.height + media.viewPadding.bottom,
        child: LiquidSearchControl(
          key: const ValueKey<String>('library_search'),
          onChanged: widget.controller.updateQuery,
        ),
      ),
      builder: (context, child) => PopScope<void>(
        canPop: widget.controller.unavailableDocument == null,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && widget.controller.unavailableDocument != null) {
            widget.controller.dismissUnavailable();
          }
        },
        child: ColoredBox(
          key: const ValueKey<String>('folio_surface'),
          color: FolioColors.background,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              const LibraryBackground(),
              _LibraryContent(
                controller: widget.controller,
                scrollController: _scrollController,
                documentContentSource: widget.documentContentSource,
                onOpenSettings: _openSettings,
                onBeginOpen: _beginReaderOpen,
                onReaderClosed: _readerClosed,
              ),
              child!,
              if (widget.controller.unavailableDocument case final document?)
                _UnavailableRecovery(
                  document: document,
                  onDismiss: widget.controller.dismissUnavailable,
                  onRecover: widget.controller.recoverUnavailable,
                  onRemove: widget.controller.removeUnavailableFromRecents,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.controller,
    required this.scrollController,
    required this.documentContentSource,
    required this.onOpenSettings,
    required this.onBeginOpen,
    required this.onReaderClosed,
  });

  final LibraryController controller;
  final ScrollController scrollController;
  final VoidCallback onOpenSettings;
  final bool Function() onBeginOpen;
  final VoidCallback onReaderClosed;
  final DocumentContentSource documentContentSource;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.viewPaddingOf(context).top;
    final recent = controller.recentDocuments;
    final documents = controller.regularDocuments;
    return ScrollEdgeFade(
      color: FolioColors.background,
      child: CustomScrollView(
        key: const ValueKey<String>('document_list'),
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topPadding + 28, 20, 19),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        const Flexible(
                          child: Text(
                            'Folio',
                            style: FolioText.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        LiquidGlassControl(
                          key: const ValueKey<String>('library_settings'),
                          size: const Size.square(36),
                          semanticsLabel: 'Settings',
                          onTap: onOpenSettings,
                          child: const AdaptiveGlassIcon(
                            LucideIcons.settings,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (controller.loadState == LibraryLoadState.ready)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        controller.isRefreshing
                            ? 'Scanning…'
                            : '${controller.totalCount} documents',
                        style: FolioText.metadata,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: LibraryFilterBar(
              selected: controller.filter,
              onSelected: controller.selectFilter,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (controller.access == LibraryAccess.denied &&
              controller.loadState == LibraryLoadState.ready)
            SliverToBoxAdapter(
              child: _PermissionNotice(
                onOpenSettings: controller.requestFullAccess,
              ),
            ),
          if (controller.refreshFailed &&
              controller.loadState == LibraryLoadState.ready)
            SliverToBoxAdapter(
              child: _RefreshFailureNotice(onRetry: controller.refresh),
            ),
          if (controller.loadState == LibraryLoadState.loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _StatusView(
                title: 'Finding your documents',
                message: 'Your library will appear here.',
              ),
            )
          else if (controller.loadState == LibraryLoadState.failed)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _StatusView(
                title: 'Library unavailable',
                message: 'Close Folio and try again.',
              ),
            )
          else if (recent.isEmpty && documents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _StatusView(
                title: controller.query.isEmpty
                    ? 'No documents yet'
                    : 'No documents found',
                message: controller.query.isEmpty
                    ? 'PDF, Word, PowerPoint and text files will appear here.'
                    : 'Try another filename or format.',
              ),
            )
          else ...<Widget>[
            if (recent.isNotEmpty) ...<Widget>[
              _SectionHeader(title: 'RECENT', count: recent.length),
              _DocumentSliver(
                documents: recent,
                controller: controller,
                documentContentSource: documentContentSource,
                onBeginOpen: onBeginOpen,
                onReaderClosed: onReaderClosed,
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 23)),
            ],
            if (documents.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: controller.query.isEmpty ? 'DOCUMENTS' : 'RESULTS',
                count: documents.length,
              ),
              _DocumentSliver(
                documents: documents,
                controller: controller,
                documentContentSource: documentContentSource,
                onBeginOpen: onBeginOpen,
                onReaderClosed: onReaderClosed,
              ),
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    LiquidSearchControlState.height +
                    MediaQuery.viewPaddingOf(context).bottom,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentSliver extends StatelessWidget {
  const _DocumentSliver({
    required this.documents,
    required this.controller,
    required this.documentContentSource,
    required this.onBeginOpen,
    required this.onReaderClosed,
  });

  final List<DocumentEntry> documents;
  final LibraryController controller;
  final DocumentContentSource documentContentSource;
  final bool Function() onBeginOpen;
  final VoidCallback onReaderClosed;

  @override
  Widget build(BuildContext context) {
    final indexById = <String, int>{
      for (var i = 0; i < documents.length; i++) documents[i].id: i,
    };
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final document = documents[index];
          return Center(
            key: ValueKey<String>(document.id),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: <Widget>[
                  _DocumentOpenContainer(
                    document: document,
                    controller: controller,
                    documentContentSource: documentContentSource,
                    onBeginOpen: onBeginOpen,
                    onReaderClosed: onReaderClosed,
                  ),
                  if (index < documents.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 82, right: 20),
                      child: SizedBox(
                        height: 0.8,
                        child: ColoredBox(color: FolioColors.separator),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        childCount: documents.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? indexById[key.value] : null,
      ),
    );
  }
}

class _DocumentOpenContainer extends StatelessWidget {
  const _DocumentOpenContainer({
    required this.document,
    required this.controller,
    required this.documentContentSource,
    required this.onBeginOpen,
    required this.onReaderClosed,
  });

  final DocumentEntry document;
  final LibraryController controller;
  final DocumentContentSource documentContentSource;
  final bool Function() onBeginOpen;
  final VoidCallback onReaderClosed;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return OpenContainer<void>(
      tappable: false,
      closedColor: const Color(0x00000000),
      openColor: FolioColors.background,
      middleColor: FolioColors.background,
      closedElevation: 0,
      openElevation: 0,
      closedShape: const RoundedRectangleBorder(),
      openShape: const RoundedRectangleBorder(),
      clipBehavior: Clip.none,
      transitionType: ContainerTransitionType.fade,
      transitionDuration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 340),
      closedBuilder: (context, openContainer) => DocumentRow(
        key: ValueKey<String>('document_${document.id}'),
        document: document,
        onTapDown: () {
          // Warm the renderer while the container morph still runs, so the
          // reader route adopts in-flight I/O instead of starting it after
          // the 340ms transition.
          ReaderPreloader.prime(
            document: document,
            contentSource: documentContentSource,
          );
        },
        onTap: () {
          if (!document.isAvailable) {
            unawaited(controller.markOpened(document));
            return;
          }
          if (!onBeginOpen()) {
            return;
          }
          try {
            openContainer();
          } catch (_) {
            onReaderClosed();
            rethrow;
          }
          // Updating Recents can move this row into another sliver. Wait until
          // the source container has finished morphing before rebuilding it.
          if (reducedMotion) {
            unawaited(controller.markOpened(document));
          } else {
            unawaited(
              Future<void>.delayed(
                const Duration(milliseconds: 360),
                () => controller.markOpened(document),
              ),
            );
          }
        },
      ),
      openBuilder: (context, closeContainer) {
        final primed = ReaderPreloader.adopt(
          document,
          contentSource: documentContentSource,
        );
        return ReaderScreen(
          document: document,
          contentSource: documentContentSource,
          deferInitialLoad: primed == null && !reducedMotion,
          initialRenderer: primed,
          onDisposed: onReaderClosed,
          onRemoveFromRecents: () => controller.removeFromRecents(document),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: <Widget>[
                Text(title, style: FolioText.section),
                const SizedBox(width: 7),
                Text('$count', style: FolioText.metadata),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x0DFFFFFF),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0x1FFFFFFF), width: 0.8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Allow file access',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: FolioColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: Text(
                      'Folio needs access to find documents stored on this device. You can still open individual files from other apps.',
                      style: FolioText.metadata,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      offset: const Offset(-40, 0),
                      child: LiquidGlassButton(
                        label: 'Open settings',
                        width: 142,
                        height: 50,
                        onTap: onOpenSettings,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableRecovery extends StatelessWidget {
  const _UnavailableRecovery({
    required this.document,
    required this.onDismiss,
    required this.onRecover,
    required this.onRemove,
  });

  final DocumentEntry document;
  final VoidCallback onDismiss;
  final VoidCallback onRecover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'File access expired',
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDismiss,
                child: const ColoredBox(color: Color(0xB8000000)),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  // Та же статичная liquid-панель, что и в ридере.
                  child: GlassPanel(
                    borderRadius: 28,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'File access expired',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: FolioColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Folio can no longer reach “${document.name}”. Select it again or remove it from Recents.',
                          textAlign: TextAlign.center,
                          style: FolioText.metadata,
                        ),
                        const SizedBox(height: 4),
                        LiquidGlassButton(
                          label: 'Grant access again',
                          width: 190,
                          height: 50,
                          onTap: onRecover,
                        ),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onRemove,
                          child: const Padding(
                            padding: EdgeInsets.fromLTRB(16, 9, 16, 15),
                            child: Text(
                              'Remove from Recents',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                color: FolioColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
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

class _RefreshFailureNotice extends StatelessWidget {
  const _RefreshFailureNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Semantics(
              button: true,
              label: 'Retry library refresh',
              child: const Text(
                'Library refresh paused. Tap to try again.',
                style: FolioText.metadata,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 110),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                color: FolioColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FolioText.metadata,
            ),
          ],
        ),
      ),
    );
  }
}
