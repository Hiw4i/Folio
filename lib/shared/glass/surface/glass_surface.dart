import 'package:flutter/widgets.dart';

import '../core/glass_geometry.dart';
import '../motion/glass_motion_controller.dart';
import 'glass_shell.dart';

class LiquidGlassSurface extends StatelessWidget {
  const LiquidGlassSurface({
    required this.frame,
    required this.motion,
    required this.focused,
    super.key,
  });

  final GlassGeometryFrame frame;
  final GlassMotionController motion;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final pointer = motion.lightPosition == Offset.zero
        ? frame.localMainRect.center
        : motion.lightPosition - frame.opticalBounds.topLeft;
    return Positioned.fromRect(
      rect: frame.opticalBounds,
      child: GlassShell(
        path: frame.buildLocalUnifiedPath(),
        glowCenter: pointer,
        press: motion.press,
        focused: focused,
        blurSigma: motion.backdropBlurSigma,
      ),
    );
  }
}
