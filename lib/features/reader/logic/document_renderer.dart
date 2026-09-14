import '../../library/data/document_entry.dart';
import '../data/document_content_source.dart';
import '../office/data/office_document_gateway.dart';
import '../pdf/logic/pdf_document_renderer.dart';
import '../powerpoint/logic/powerpoint_document_renderer.dart';
import '../text/data/text_document.dart';
import '../text/logic/text_document_renderer.dart';
import '../word/logic/word_document_renderer.dart';
import 'document_renderer_contract.dart';

export '../office/logic/office_document_renderer_base.dart';
export '../pdf/logic/pdf_document_renderer.dart';
export '../powerpoint/logic/powerpoint_document_renderer.dart';
export '../text/logic/text_document_renderer.dart';
export '../word/logic/word_document_renderer.dart';
export 'document_renderer_contract.dart';
export 'unsupported_document_renderer.dart';

DocumentRenderer createDocumentRenderer({
  required DocumentEntry document,
  required DocumentContentSource contentSource,
}) {
  return switch (document.format) {
    DocumentFormat.pdf => PdfDocumentRenderer(
      document: document,
      contentSource: contentSource,
    ),
    DocumentFormat.docx => WordDocumentRenderer(
      document: document,
      gateway: const DeviceOfficeDocumentGateway(),
    ),
    DocumentFormat.pptx => PowerPointDocumentRenderer(
      document: document,
      gateway: const DeviceOfficeDocumentGateway(),
    ),
    DocumentFormat.txt || DocumentFormat.markdown => TextDocumentRenderer(
      document: document,
      loader: TextDocumentLoader(contentSource),
    ),
  };
}
