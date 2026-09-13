import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.borderRadius = 24,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  static final ui.ImageFilter _blur = ui.ImageFilter.blur(
    sigmaX: 16,
    sigmaY: 16,
    tileMode: ui.TileMode.mirror,
  );

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x52000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: _blur,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xB31A1B1E),
                borderRadius: radius,
                border: Border.all(color: const Color(0x42FFFFFF), width: 0.8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0x1FFFFFFF), Color(0x08FFFFFF)],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
