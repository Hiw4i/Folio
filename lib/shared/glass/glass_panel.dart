import 'package:flutter/widgets.dart';

import 'liquid_surface.dart';

/// Static liquid panel: non-interactive mode of the same liquid library.
///
/// Shares blur/shadow/rim with every other surface via [LiquidCase]; only
/// the opaque fill differs (readability for text content).
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

  @override
  Widget build(BuildContext context) {
    return LiquidCase(
      borderRadius: borderRadius,
      padding: padding,
      child: child,
    );
  }
}
