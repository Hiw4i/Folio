import 'dart:async';

import 'package:flutter/material.dart'
    show
        ContextMenuButtonItem,
        ContextMenuButtonType,
        DefaultMaterialLocalizations,
        TextSelectionToolbarAnchors;
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../shared/selection/folio_selection_toolbar.dart';
import '../../../../shared/theme/folio_theme.dart';
import '../../widgets/reader_loading_view.dart';
import '../logic/pdf_document_renderer.dart';
import '../logic/pdf_reading_layout.dart';

class PdfDocumentView extends StatefulWidget {
  const PdfDocumentView({
    required this.renderer,
    required this.onContentTap,
    required this.onVerticalReadingGesture,
    super.key,
  });

  final PdfDocumentRenderer renderer;
  final VoidCallback onContentTap;
  final ValueChanged<double> onVerticalReadingGesture;

  @override
  State<PdfDocumentView> createState() => _PdfDocumentViewState();
}

class _PdfDocumentViewState extends State<PdfDocumentView> {
  static const int _renderCacheBudget = 128 * 1024 * 1024;

  final PdfViewerController _controller = PdfViewerController();
  late final PdfViewerParams _params;
  bool _selectingText = false;

  @override
  void initState() {
    super.initState();
    _params = PdfViewerParams(
      margin: 0,
      layoutPages: layoutPdfReadingPages,
      sizeDelegateProvider: pdfReadingSizeDelegateProvider,
      backgroundColor: FolioColors.background,
      pageDropShadow: const BoxShadow(
        color: Color(0x7A000000),
        blurRadius: 12,
        spreadRadius: 1,
        offset: Offset(0, 5),
      ),
      limitRenderingCache: true,
      maxImageBytesCachedOnMemory: _renderCacheBudget,
      horizontalCacheExtent: 0.35,
      verticalCacheExtent: 0.85,
      onePassRenderingSizeThreshold: 2400,
      textSelectionParams: PdfTextSelectionParams(
        enabled: true,
        enableSelectionHandles: true,
        showContextMenuAutomatically: true,
        onTextSelectionChange: _textSelectionChanged,
      ),
      buildContextMenu: _buildContextMenu,
      scrollPhysics: const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      ),
      scrollPhysicsScale: const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      ),
      matchTextColor: FolioColors.pdfSearchMatch,
      activeMatchTextColor: FolioColors.pdfActiveSearchMatch,
      pagePaintCallbacks: <PdfViewerPagePaintCallback>[
        widget.renderer.paintSearchMatches,
      ],
      behaviorControlParams: const PdfViewerBehaviorControlParams(
        loadPageDimensionsOnDemand: true,
        trailingPageLoadingDelay: Duration(milliseconds: 90),
        enableLowResolutionPagePreview: true,
      ),
      onViewerReady: widget.renderer.attachViewer,
      onDocumentLoadFinished: widget.renderer.documentLoadFinished,
      onPageChanged: widget.renderer.pageChanged,
      onInteractionUpdate: _interactionUpdated,
      onGeneralTap: _generalTap,
      loadingBannerBuilder: (context, downloaded, total) {
        // Same unified surface as every other format: dots plus the single
        // `Opening document` line.
        return ColoredBox(
          color: FolioColors.background,
          child: ReaderLoadingView(
            document: widget.renderer.document,
            immediate: true,
          ),
        );
      },
      errorBannerBuilder: (context, error, stackTrace, ref) {
        return const SizedBox.shrink();
      },
    );
  }

  void _interactionUpdated(ScaleUpdateDetails details) {
    if (_selectingText || (details.scale - 1).abs() > 0.015) {
      return;
    }
    final scrollDelta = -details.focalPointDelta.dy;
    if (scrollDelta != 0) {
      widget.onVerticalReadingGesture(scrollDelta);
    }
  }

  void _textSelectionChanged(PdfTextSelection selection) {
    _selectingText = selection.hasSelectedText;
  }

  Widget? _buildContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final items = <ContextMenuButtonItem>[
      if (params.isTextSelectionEnabled &&
          params.textSelectionDelegate.isCopyAllowed &&
          params.textSelectionDelegate.hasSelectedText)
        ContextMenuButtonItem(
          onPressed: params.textSelectionDelegate.copyTextSelection,
          type: ContextMenuButtonType.copy,
        ),
      if (params.isTextSelectionEnabled &&
          !params.textSelectionDelegate.isSelectingAllText)
        ContextMenuButtonItem(
          onPressed: params.textSelectionDelegate.selectAllText,
          type: ContextMenuButtonType.selectAll,
        ),
    ];
    if (items.isEmpty) {
      return null;
    }
    return PdfSelectionContextMenu(
      primaryAnchor: params.anchorA,
      secondaryAnchor: params.anchorB,
      buttonItems: items,
    );
  }

  bool _generalTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    switch (details.type) {
      case PdfViewerGeneralTapType.tap:
        widget.onContentTap();
        return false;
      case PdfViewerGeneralTapType.doubleTap:
        unawaited(controller.zoomUp(loop: true));
        return true;
      case PdfViewerGeneralTapType.longPress ||
          PdfViewerGeneralTapType.secondaryTap:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final documentRef = widget.renderer.documentRef;
    if (documentRef == null) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      key: const ValueKey<String>('pdf_document_view'),
      child: PdfViewer(documentRef, controller: _controller, params: _params),
    );
  }
}

/// Keeps the PDF selection overlay self-contained. pdfrx builds this widget
/// inside the viewer overlay, which is not guaranteed to retain the app-level
/// Material localizations on every Android composition path.
class PdfSelectionContextMenu extends StatelessWidget {
  const PdfSelectionContextMenu({
    required this.primaryAnchor,
    required this.buttonItems,
    this.secondaryAnchor,
    super.key,
  });

  final Offset primaryAnchor;
  final Offset? secondaryAnchor;
  final List<ContextMenuButtonItem> buttonItems;

  @override
  Widget build(BuildContext context) {
    return Localizations.override(
      context: context,
      locale: const Locale('en'),
      delegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
      ],
      child: Align(
        alignment: Alignment.topLeft,
        child: FolioSelectionToolbar(
          anchors: TextSelectionToolbarAnchors(
            primaryAnchor: primaryAnchor,
            secondaryAnchor: secondaryAnchor,
          ),
          buttonItems: buttonItems,
        ),
      ),
    );
  }
}
