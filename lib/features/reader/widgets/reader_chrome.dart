import 'package:flutter/widgets.dart';

/// Shared show/hide spec for every reader control.
///
/// One [AnimationController] (owned by `ReaderScreen`) drives all five
/// controls as a single whole: top bar, progress pill, bottom search,
/// morphing menu and search navigator. Pixel offsets keep the travel short
/// (iOS-style nudge + fade) so hidden controls leave the screen fast and,
/// once dismissed, are fully unmounted — no `BackdropFilter` cost while
/// reading.
abstract final class ReaderChromeSpec {
  static const Duration showDuration = Duration(milliseconds: 420);
  static const Duration hideDuration = Duration(milliseconds: 420);

  static const Curve showCurve = Curves.easeOutCubic;
  static const Curve hideCurve = Curves.easeInCubic;

  /// A short intentional drag is required before chrome changes direction.
  /// This filters touch jitter, bounce-back and tiny reading corrections.
  static const double scrollIntentDistance = 12;

  /// Top controls slide up, bottom controls slide down, pills nudge.
  static const double topHiddenDy = -56;
  static const double bottomHiddenDy = 56;
  static const double pillHiddenDy = 56;
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
/// - While moving, the whole chrome is composited as one lightweight layer.
///   In particular, do not propagate the animation value into every glass
///   surface: changing a backdrop blur for each frame forces several costly
///   backdrop passes over the scrolling document. Hit testing and semantics
///   follow `t < 0.5`.
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
              child: ExcludeSemantics(excluding: false, child: child!),
            ),
          );
        }
        final dy = hiddenDy * (1 - t);
        final inactive = t < 0.5;
        return RepaintBoundary(
          child: IgnorePointer(
            ignoring: inactive,
            child: ExcludeSemantics(
              excluding: inactive,
              child: Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, dy), child: child),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
