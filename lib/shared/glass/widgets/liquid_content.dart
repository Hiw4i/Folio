import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/liquid_shape.dart';

/// Shared foreground helpers so every liquid surface moves its content
/// identically: slight inertial follow, subtle press scale and a small
/// velocity blur while the material springs.
///
/// Search is the reference: [LiquidShape.contentOffset] with `follow 0.26`,
/// `maximum 6.5`, [LiquidShape.contentScale] and [LiquidShape.motionBlurSigma]
/// clamped to `2.15`.
abstract final class LiquidContent {
  static final Map<double, ui.ImageFilter> _softeningFilters =
      <double, ui.ImageFilter>{};

  static Offset offset({
    required Offset displacement,
    Offset velocity = Offset.zero,
    double press = 0,
  }) => LiquidShape.contentOffset(
    displacement: displacement,
    velocity: velocity,
    press: press,
  );

  static double scale(double press) => LiquidShape.contentScale(press);

  static double blurSigma({
    required double morphVelocity,
    double separationVelocity = 0,
    required bool reducedMotion,
  }) => LiquidShape.motionBlurSigma(
    morphVelocity: morphVelocity,
    separationVelocity: separationVelocity,
    reducedMotion: reducedMotion,
  );

  /// Applies the velocity blur used while the material springs. Returns
  /// [child] untouched when the blur is negligible to avoid a needless
  /// `ImageFiltered` layer.
  static Widget soften({required Widget child, required double sigma}) {
    if (sigma <= 0.01) {
      return child;
    }
    return ImageFiltered(imageFilter: softeningFilterFor(sigma), child: child);
  }

  /// Motion blur is visually insensitive to a tenth-pixel step, while the
  /// quantization keeps native [ui.ImageFilter] allocation out of animation
  /// frames. This stays separate from [LiquidBlur] because content blur uses
  /// [ui.TileMode.decal], not backdrop's mirror mode.
  static ui.ImageFilter softeningFilterFor(double sigma) {
    final quantized = (sigma * 10).roundToDouble() / 10;
    var filter = _softeningFilters[quantized];
    if (filter == null) {
      if (_softeningFilters.length >= 32) {
        _softeningFilters.clear();
      }
      filter = ui.ImageFilter.blur(
        sigmaX: quantized,
        sigmaY: quantized,
        tileMode: ui.TileMode.decal,
      );
      _softeningFilters[quantized] = filter;
    }
    return filter;
  }

  /// Follows the material with inertia: translate + press scale in one place.
  static Widget follow({
    required Widget child,
    required Offset displacement,
    Offset velocity = Offset.zero,
    double press = 0,
  }) {
    return Transform.translate(
      offset: offset(
        displacement: displacement,
        velocity: velocity,
        press: press,
      ),
      child: Transform.scale(scale: scale(press), child: child),
    );
  }
}
