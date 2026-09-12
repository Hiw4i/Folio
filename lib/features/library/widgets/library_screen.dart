import 'package:fading_edge_scrollview/fading_edge_scrollview.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/glass/liquid_glass_button.dart';
import '../../../shared/glass/liquid_search_control.dart';
import '../../../shared/theme/folio_theme.dart';
import '../data/document_entry.dart';
import '../data/library_repository.dart';
import '../logic/library_controller.dart';
import 'document_row.dart';
import 'library_background.dart';
import 'library_filter_bar.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({required this.controller, super.key});

  final LibraryController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.load();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return ColoredBox(
      key: const ValueKey<String>('folio_surface'),
      color: FolioColors.background,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const LibraryBackground(),
          AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) => _LibraryContent(
              controller: widget.controller,
              scrollController: _scrollController,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: media.viewInsets.bottom,
            height: LiquidSearchControlState.height + media.viewPadding.bottom,
            child: LiquidSearchControl(
              key: const ValueKey<String>('library_search'),
              onChanged: widget.controller.updateQuery,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryContent extends StatelessWidget {
  const _LibraryContent({
    required this.controller,
    required this.scrollController,
  });

  final LibraryController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.viewPaddingOf(context).top;
    final recent = controller.recentDocuments;
    final documents = controller.regularDocuments;
    return FadingEdgeScrollView.fromScrollView(
      gradientFractionOnStart: 0.055,
      gradientFractionOnEnd: 0.12,
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
                  const Expanded(child: Text('Folio', style: FolioText.title)),
                  if (controller.loadState == LibraryLoadState.ready)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '${controller.totalCount} documents',
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
            const SliverToBoxAdapter(child: _PermissionNotice()),
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
              _DocumentSliver(documents: recent, onOpen: controller.open),
              const SliverToBoxAdapter(child: SizedBox(height: 23)),
            ],
            if (documents.isNotEmpty) ...<Widget>[
              _SectionHeader(
                title: controller.query.isEmpty ? 'DOCUMENTS' : 'RESULTS',
                count: documents.length,
              ),
              _DocumentSliver(documents: documents, onOpen: controller.open),
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
  const _DocumentSliver({required this.documents, required this.onOpen});

  final List<DocumentEntry> documents;
  final ValueChanged<DocumentEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final document = documents[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: <Widget>[
                DocumentRow(
                  key: ValueKey<String>('document_${document.id}'),
                  document: document,
                  onTap: () => onOpen(document),
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
      }, childCount: documents.length),
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
  const _PermissionNotice();

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
                        onTap: _prototypeAction,
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

  static void _prototypeAction() {}
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
