import 'package:flutter/widgets.dart';

import '../../../shared/theme/folio_theme.dart';
import '../data/document_entry.dart';

class DocumentRow extends StatefulWidget {
  const DocumentRow({
    required this.document,
    required this.onTap,
    this.onTapDown,
    super.key,
  });

  final DocumentEntry document;
  final VoidCallback onTap;
  final VoidCallback? onTapDown;

  @override
  State<DocumentRow> createState() => _DocumentRowState();
}

class _DocumentRowState extends State<DocumentRow> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final document = widget.document;
    return Semantics(
      button: true,
      label: '${document.name}, ${formatFileSize(document.sizeBytes)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          _setPressed(true);
          widget.onTapDown?.call();
        },
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed && !reducedMotion ? 0.986 : 1,
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 120),
            color: _pressed ? const Color(0x0FFFFFFF) : const Color(0x00000000),
            padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
            child: SizedBox(
              height: 56,
              child: Row(
                children: <Widget>[
                  _FormatGlyph(format: document.format),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          document.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FolioText.filename,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          formatFileSize(document.sizeBytes),
                          style: FolioText.metadata,
                        ),
                      ],
                    ),
                  ),
                  if (!document.isAvailable)
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text(
                        'Unavailable',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: FolioColors.textTertiary,
                          fontSize: 11,
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

class _FormatGlyph extends StatelessWidget {
  const _FormatGlyph({required this.format});

  final DocumentFormat format;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0x0BFFFFFF),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0x1FFFFFFF), width: 0.8),
      ),
      alignment: Alignment.center,
      child: Icon(
        format.icon,
        size: 24,
        color: FolioColors.textPrimary.withValues(alpha: 0.88),
      ),
    );
  }
}

String formatFileSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
