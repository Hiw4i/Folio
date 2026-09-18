import 'package:flutter/widgets.dart';

import 'adaptive_glass_foreground.dart';
import 'liquid_glass_control.dart';

class LiquidGlassButton extends StatelessWidget {
  const LiquidGlassButton({
    required this.label,
    required this.onTap,
    this.width = 168,
    this.height = 56,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LiquidGlassControl(
      semanticsLabel: label,
      size: Size(width, height),
      onTap: onTap,
      child: AdaptiveGlassText(
        label,
        maxLines: 1,
        style: const TextStyle(
          fontFamily: 'Inter',
          color: Color(0xFFF4F3EF),
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
