import '../../../library/data/document_entry.dart';
import '../../office/logic/office_document_renderer_base.dart';

class PowerPointDocumentRenderer extends OfficeDocumentRendererBase {
  PowerPointDocumentRenderer({required super.document, required super.gateway})
    : assert(document.format == DocumentFormat.pptx);
}
