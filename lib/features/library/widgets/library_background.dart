import 'package:flutter/widgets.dart';

import '../../../shared/theme/folio_theme.dart';

class LibraryBackground extends StatelessWidget {
  const LibraryBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: FolioColors.background,
          gradient: RadialGradient(
            center: Alignment(0.75, -0.65),
            radius: 1.05,
            colors: <Color>[
              Color(0xFF292824),
              Color(0xFF131416),
              FolioColors.background,
            ],
            stops: <double>[0, 0.42, 1],
          ),
        ),
        child: CustomPaint(painter: _AtmospherePainter()),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  const _AtmospherePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0x08FFFFFF)
      ..strokeWidth = 0.6;
    const spacing = 36.0;
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) => false;
}
