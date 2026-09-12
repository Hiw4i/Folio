import 'package:flutter/widgets.dart';

@immutable
class LiquidShapeTokens {
  const LiquidShapeTokens({
    this.pressGrowth = 0.055,
    this.travelGrowth = 0.09,
    this.travelStretch = 0.34,
  });

  final double pressGrowth;
  final double travelGrowth;
  final double travelStretch;
}

/// Resolves the material bounds shared by buttons, morphs and moving lenses.
abstract final class LiquidShape {
  static Rect expandedRect(
    Rect rect, {
    double press = 0,
    double travel = 0,
    LiquidShapeTokens tokens = const LiquidShapeTokens(),
  }) {
    final safePress = press.clamp(0.0, 1.08);
    final safeTravel = travel.clamp(0.0, 1.08);
    final commonGrowth =
        safePress * tokens.pressGrowth + safeTravel * tokens.travelGrowth;
    return Rect.fromCenter(
      center: rect.center,
      width:
          rect.width * (1 + commonGrowth + safeTravel * tokens.travelStretch),
      height: rect.height * (1 + commonGrowth),
    );
  }
}
