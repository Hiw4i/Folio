import 'package:flutter/widgets.dart';

@immutable
class MotionTokens {
  const MotionTokens({
    required this.morph,
    required this.separation,
    required this.pointerReturn,
    required this.press,
    required this.maxDrag,
    required this.dragGain,
    required this.velocityGain,
    required this.tapSlop,
  });

  const MotionTokens.standard()
    : morph = const SpringDescription(mass: 1, stiffness: 140, damping: 18),
      separation = const SpringDescription(
        mass: 0.78,
        stiffness: 200,
        damping: 17.5,
      ),
      pointerReturn = const SpringDescription(
        mass: 2.92,
        stiffness: 660,
        damping: 40,
      ),
      press = const SpringDescription(mass: 1, stiffness: 780, damping: 32),
      maxDrag = 30,
      dragGain = 0.16,
      velocityGain = 0.11,
      tapSlop = 8;

  const MotionTokens.reduced()
    : morph = const SpringDescription(mass: 1, stiffness: 620, damping: 50),
      separation = const SpringDescription(
        mass: 0.8,
        stiffness: 690,
        damping: 50,
      ),
      pointerReturn = const SpringDescription(
        mass: 1,
        stiffness: 680,
        damping: 52,
      ),
      press = const SpringDescription(mass: 1, stiffness: 760, damping: 54),
      maxDrag = 4,
      dragGain = 0.12,
      velocityGain = 0.02,
      tapSlop = 8;

  final SpringDescription morph;
  final SpringDescription separation;
  final SpringDescription pointerReturn;
  final SpringDescription press;
  final double maxDrag;
  final double dragGain;
  final double velocityGain;
  final double tapSlop;
}

@immutable
class GlassTokens {
  const GlassTokens({
    this.collapsedDiameter = 68,
    this.expandedHeight = 64,
    this.cancelWidth = 92,
    this.cancelHeight = 54,
    this.settledGap = 12,
    this.horizontalMargin = 16,
    this.maxSearchWidth = 420,
    this.opticalMargin = 44,
    this.blurSigma = 13.5,
  });

  final double collapsedDiameter;
  final double expandedHeight;
  final double cancelWidth;
  final double cancelHeight;
  final double settledGap;
  final double horizontalMargin;
  final double maxSearchWidth;
  final double opticalMargin;
  final double blurSigma;
}
