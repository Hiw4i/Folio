import 'package:flutter/widgets.dart';

import '../widgets/liquid_container.dart';

/// Content-sized panel backed by the shared liquid library.
///
/// Static by default. [liquidMotion] opts into the existing deforming material
/// while keeping inner cards, controls and scrolling stationary.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.borderRadius = 24,
    this.padding = EdgeInsets.zero,
    this.liquidMotion = false,
    super.key,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool liquidMotion;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.panel(
      liquidMotion: liquidMotion,
      borderRadius: borderRadius,
      padding: padding,
      child: child,
    );
  }
}
