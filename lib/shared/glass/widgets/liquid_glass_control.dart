import 'package:flutter/widgets.dart';

import '../core/liquid_shape.dart';
import 'liquid_container.dart';

/// Reusable liquid-glass interaction primitive for text, icons and future
/// compound controls. It owns hit testing, focus, pointer physics and painting;
/// callers only provide content and an action.
///
/// Thin facade over the universal [LiquidGlass.fixed] substance so buttons,
/// pills and passive spots share one physics/painting implementation.
class LiquidGlassControl extends StatelessWidget {
  const LiquidGlassControl({
    required this.child,
    required this.size,
    this.onTap,
    this.semanticsLabel,
    this.shapeTokens = const LiquidShapeTokens(),
    this.hitSlop = 8,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final Size size;
  final LiquidShapeTokens shapeTokens;
  final double hitSlop;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.fixed(
      size: size,
      onTap: onTap,
      semanticsLabel: semanticsLabel,
      shapeTokens: shapeTokens,
      hitSlop: hitSlop,
      child: child,
    );
  }
}
