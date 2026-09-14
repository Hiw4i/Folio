import 'package:flutter/widgets.dart';

import '../../office/widgets/office_document_platform_view.dart';
import '../logic/powerpoint_document_renderer.dart';

class PowerPointDocumentView extends StatelessWidget {
  const PowerPointDocumentView({
    required this.renderer,
    required this.onContentTap,
    required this.onReadingGesture,
    super.key,
  });

  final PowerPointDocumentRenderer renderer;
  final VoidCallback onContentTap;
  final ValueChanged<double> onReadingGesture;

  @override
  Widget build(BuildContext context) {
    return OfficeDocumentPlatformView(
      renderer: renderer,
      onContentTap: onContentTap,
      onReadingGesture: onReadingGesture,
    );
  }
}
