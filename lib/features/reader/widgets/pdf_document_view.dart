import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../shared/theme/folio_theme.dart';
import '../logic/document_renderer.dart';

class PdfDocumentView extends StatefulWidget {
  const PdfDocumentView({
    required this.renderer,
    required this.onContentTap,
    required this.onVerticalReadingGesture,
    super.key,
  });

  final PdfDocumentRenderer renderer;
  final VoidCallback onContentTap;
  final ValueChanged<bool> onVerticalReadingGesture;

  @override
  State<PdfDocumentView> createState() => _PdfDocumentViewState();
}

class _PdfDocumentViewState extends State<PdfDocumentView> {
  static const int _renderCacheBudget = 128 * 1024 * 1024;

  final PdfViewerController _controller = PdfViewerController();
  late final PdfViewerParams _params;
  double _verticalGestureTravel = 0;

  @override
  void initState() {
    super.initState();
    _params = PdfViewerParams(
      margin: 12,
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
      scrollPhysics: const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      ),
      scrollPhysicsScale: const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      ),
      matchTextColor: const Color(0x55E7C768),
      activeMatchTextColor: const Color(0xB8E7C768),
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
      onInteractionStart: (_) => _verticalGestureTravel = 0,
      onInteractionUpdate: _interactionUpdated,
      onGeneralTap: _generalTap,
      loadingBannerBuilder: (context, downloaded, total) {
        return const ColoredBox(
          color: FolioColors.background,
          child: Center(
            child: Text(
              'Opening PDF…',
              style: TextStyle(
                fontFamily: 'Inter',
                color: FolioColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
      errorBannerBuilder: (context, error, stackTrace, ref) {
        return const SizedBox.shrink();
      },
    );
  }

  void _interactionUpdated(ScaleUpdateDetails details) {
    if ((details.scale - 1).abs() > 0.015) {
      return;
    }
    _verticalGestureTravel += details.focalPointDelta.dy;
    if (_verticalGestureTravel.abs() >= 9) {
      widget.onVerticalReadingGesture(_verticalGestureTravel < 0);
      _verticalGestureTravel = 0;
    }
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
