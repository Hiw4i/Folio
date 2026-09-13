import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';

/// Canonical liquid surfaces: one blur, one shadow language, one rim.
///
/// Interactive (deformed) surfaces keep using `GlassShell` directly — it
/// already shares [LiquidBlur.filter]. Static surfaces (panels, segmented
/// tracks) use [LiquidCase] so they stop drifting apart with their own
/// blur sigmas (11 vs 13.5 vs 16) and border colors.
abstract final class LiquidBlur {
  /// Single shared backdrop filter for every liquid surface.
  ///
  /// Previously `GlassShell` used 13.5, the segmented track 11 and
  /// `GlassPanel` 16 — now all resolve to [GlassTokens.blurSigma].
  static final ui.ImageFilter filter = ui.ImageFilter.blur(
    sigmaX: const GlassTokens().blurSigma,
    sigmaY: const GlassTokens().blurSigma,
    tileMode: ui.TileMode.mirror,
  );
}

/// Static (non-deforming) liquid shell: the `GlassPanel` look as a mode of
/// the same library instead of a separate implementation.
///
/// [fill] varies by use case (translucent track vs opaque panel with text)
/// but blur, shadow, rim and gradient overlay are shared.
class LiquidCase extends StatelessWidget {
  const LiquidCase({
    required this.child,
    this.borderRadius = 24,
    this.padding = EdgeInsets.zero,
    this.fill = const Color(0xB31A1B1E),
    super.key,
  });

  /// Translucent track behind a moving lens (segmented control).
  const LiquidCase.track({super.key})
    : child = const SizedBox.expand(),
      borderRadius = 27,
      padding = EdgeInsets.zero,
      fill = const Color(0x161A1B1D);

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          // Same shadow language as GlassShell (offset y=7-8, soft black).
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x3D020809),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: LiquidBlur.filter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: radius,
                border: Border.all(
                  color: const Color(0x42FFFFFF),
                  width: 0.8,
                ),
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
