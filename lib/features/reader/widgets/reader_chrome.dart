import 'package:flutter/widgets.dart';

import '../../../shared/glass/core/glass_tokens.dart';
import '../../../shared/glass/surface/liquid_surface.dart';

/// Shared show/hide spec for every reader control.
///
/// One [AnimationController] (owned by `ReaderScreen`) drives all five
/// controls as a single whole: top bar, progress pill, bottom search,
/// morphing menu and search navigator. Pixel offsets keep the travel short
/// (iOS-style nudge + fade) so hidden controls leave the screen fast and,
/// once dismissed, are fully unmounted — no `BackdropFilter` cost while
/// reading.
abstract final class ReaderChromeSpec {
  static const Duration showDuration = Duration(milliseconds: 360);
  static const Duration hideDuration = Duration(milliseconds: 230);

  static const Curve showCurve = Curves.easeOutCubic;
  static const Curve hideCurve = Curves.easeInCubic;

  /// Top controls slide up, bottom controls slide down, pills nudge.
  static const double topHiddenDy = -56;
  static const double bottomHiddenDy = 96;
  static const double pillHiddenDy = 24;
}

/// iOS-style slide wrapper driven by a shared chrome animation.
///
/// - `progress`: 0 = hidden, 1 = shown (already curved with asymmetric
///   forward/reverse curves).
/// - `hiddenDy`: pixel travel when hidden (negative = up, positive = down).
/// - When fully shown the child is returned without [Opacity]/[Transform]
///   so idle frames and goldens stay pixel-identical and layer-free.
/// - When dismissed the subtree is replaced with a shrink box, unmounting
///   every `BackdropFilter` inside (max scroll FPS).
/// - Mid-flight frames ease blur from 0 to the resting 12 px sigma while the
///   chrome translates. Do not place an [Opacity] above the child:
///   [BackdropFilter] then receives a transparent save layer and cannot blur
///   the actual reader content until the final frame. Hit testing and
///   semantics follow `t < 0.5`.
class ReaderChromeShell extends StatelessWidget {
  const ReaderChromeShell({
    required this.progress,
    required this.hiddenDy,
    required this.child,
    super.key,
  });

  final Animation<double> progress;
  final double hiddenDy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        if (t <= 0.001) {
          return const SizedBox.shrink();
        }
        if (t >= 0.999) {
          return RepaintBoundary(
            child: IgnorePointer(
              ignoring: false,
              child: ExcludeSemantics(
                excluding: false,
                child: child!,
              ),
            ),
          );
        }
        final dy = hiddenDy * (1 - t);
        final inactive = t < 0.5;
        return RepaintBoundary(
          child: LiquidBlurScope(
            sigma: const GlassTokens().blurSigma * t,
            opacity: t,
            child: IgnorePointer(
              ignoring: inactive,
              child: ExcludeSemantics(
                excluding: inactive,
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
