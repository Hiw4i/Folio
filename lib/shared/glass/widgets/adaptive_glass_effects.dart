import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'liquid_content.dart';

/// Foreground-only effects. Unlike Opacity/ImageFiltered, this does not put a
/// backdrop-reading glyph into an empty offscreen buffer. Adaptive glyphs apply
/// opacity to their alpha and blur *after* resolving the backdrop's color.
///
/// Wrap only foreground content, never a glass shell. Non-adaptive decorations
/// in that content (a divider, selection or caret) use [AdaptiveGlassDecoration].
class AdaptiveGlassEffects extends StatelessWidget {
  const AdaptiveGlassEffects({
    required this.child,
    this.opacity = 1,
    this.blurSigma = 0,
    super.key,
  }) : assert(opacity >= 0 && opacity <= 1),
       assert(blurSigma >= 0 && blurSigma < double.infinity);

  final Widget child;
  final double opacity;
  final double blurSigma;

  static AdaptiveGlassEffectData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EffectScope>()?.data ??
      const AdaptiveGlassEffectData();

  @override
  Widget build(BuildContext context) {
    final parent = of(context);
    return _EffectScope(
      data: AdaptiveGlassEffectData(
        opacity: (parent.opacity * opacity).clamp(0.0, 1.0),
        // Gaussian variances add when nested blur filters are composed.
        blurSigma: math.sqrt(
          parent.blurSigma * parent.blurSigma + blurSigma * blurSigma,
        ),
      ),
      child: child,
    );
  }
}

@immutable
class AdaptiveGlassEffectData {
  const AdaptiveGlassEffectData({this.opacity = 1, this.blurSigma = 0});

  final double opacity;
  final double blurSigma;

  @override
  bool operator ==(Object other) =>
      other is AdaptiveGlassEffectData &&
      other.opacity == opacity &&
      other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(opacity, blurSigma);
}

class _EffectScope extends InheritedWidget {
  const _EffectScope({required this.data, required super.child});

  final AdaptiveGlassEffectData data;

  @override
  bool updateShouldNotify(_EffectScope oldWidget) => data != oldWidget.data;
}

/// Applies foreground effects to content that does not sample a backdrop.
/// Do not wrap AdaptiveGlassText/Icon in this widget: it deliberately uses the
/// ordinary Flutter opacity/image-filter pipeline for non-adaptive content.
class AdaptiveGlassDecoration extends StatelessWidget {
  const AdaptiveGlassDecoration({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effects = AdaptiveGlassEffects.of(context);
    // Keep the element/render topology stable at opacity 0/1 and sigma 0.
    // In particular, a changing motion blur must not remount EditableText.
    return ImageFiltered(
      enabled: effects.blurSigma > 0.01,
      imageFilter: LiquidContent.softeningFilterFor(effects.blurSigma),
      child: Opacity(opacity: effects.opacity, child: child),
    );
  }
}
