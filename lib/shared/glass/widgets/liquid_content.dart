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
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: ui.TileMode.decal,
      ),
      child: child,
    );
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
