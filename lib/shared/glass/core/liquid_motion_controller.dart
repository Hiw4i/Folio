import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';

/// Shared fixed-step driver for every interactive liquid-glass component.
///
/// Subclasses only describe one integration step and their resting state. This
/// keeps buttons, morphs and future controls on the same deterministic 120 Hz
/// simulation without tying their state models together.
abstract class LiquidMotionController extends ChangeNotifier {
  LiquidMotionController({TickerProvider? vsync}) {
    final ticker = vsync?.createTicker(_onTick);
    _ticker = ticker;
    ticker?.start();
  }

  static const double fixedStep = 1 / 120;
  static const int _maxSubsteps = 4;

  Ticker? _ticker;
  Duration? _lastTick;
  double _accumulator = 0;

  @protected
  bool get isAtRest;

  @protected
  void integrate(double dt);

  @protected
  void wake() {
    _ticker?.muted = false;
  }

  /// Adaptive backdrop clarity: 1.0 at rest (full [GlassTokens.blurSigma]),
  /// easing down while the material moves fast. Subclasses feed it inside
  /// [integrate] and gate [isAtRest] on its return; surfaces read
  /// [backdropBlurSigma]. Snaps exactly to 1.0 when settled, so rest frames
  /// stay pixel-identical.
  double backdropScale = 1.0;

  double get backdropBlurSigma {
    const tokens = GlassTokens();
    if (backdropScale >= 0.999) {
      return tokens.blurSigma;
    }
    final sigma = tokens.blurSigma * backdropScale;
    return (sigma * 2).roundToDouble() / 2;
  }

  @protected
  void trackBackdropBlur({
    required double pointerSpeedPx,
    double morphSpeed = 0,
    required double dt,
  }) {
    backdropScale = LiquidBackdropAdapt.approach(
      value: backdropScale,
      target: LiquidBackdropAdapt.targetScale(pointerSpeedPx, morphSpeed),
      dt: dt,
    );
  }

  @visibleForTesting
  void stepForTest(double seconds) {
    var remaining = seconds.clamp(0.0, 1.0);
    while (remaining > 0) {
      final step = math.min(fixedStep, remaining);
      integrate(step);
      remaining -= step;
    }
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final previous = _lastTick;
    _lastTick = elapsed;
    if (previous == null) {
      return;
    }
    final frameDelta = math.min(
      (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond,
      1 / 30,
    );
    _accumulator += frameDelta;
    var steps = 0;
    while (_accumulator >= fixedStep && steps < _maxSubsteps) {
      integrate(fixedStep);
      _accumulator -= fixedStep;
      steps++;
    }
    if (steps == _maxSubsteps) {
      _accumulator = math.min(_accumulator, fixedStep);
    }
    notifyListeners();
    if (isAtRest) {
      _ticker?.muted = true;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

abstract final class LiquidSpring {
  static (double, double) scalar({
    required double position,
    required double velocity,
    required double target,
    required SpringDescription spring,
    required double dt,
  }) {
    final acceleration =
        (spring.stiffness * (target - position) - spring.damping * velocity) /
        spring.mass;
    final nextVelocity = velocity + acceleration * dt;
    return (position + nextVelocity * dt, nextVelocity);
  }

  static (Offset, Offset) offset({
    required Offset position,
    required Offset velocity,
    required Offset target,
    required SpringDescription spring,
    required double dt,
  }) {
    final acceleration =
        (target - position) * (spring.stiffness / spring.mass) -
        velocity * (spring.damping / spring.mass);
    final nextVelocity = velocity + acceleration * dt;
    return (position + nextVelocity * dt, nextVelocity);
  }

  static Offset limitOffset(Offset value, double maximum) {
    if (value == Offset.zero || value.distance <= maximum) {
      return value;
    }
    return value / value.distance * maximum;
  }
}

/// Single policy for the iOS-style adaptive backdrop blur shared by every
/// liquid controller: full blur below [_fullSpeed], minimum blur at/above
/// [_floorSpeed], fast attack so the saving applies while moving, slower
/// release so the restore never shimmers.
abstract final class LiquidBackdropAdapt {
  static const double _fullSpeed = 250.0;
  static const double _floorSpeed = 3200.0;
  static const double _attackRate = 25.0;

  /// Fast release (~100ms): the restore always finishes before the legacy
  /// rest gates, so the ticker mute rhythm — and golden capture frames —
  /// stay exactly as before. The 0.5-quantized sigma hides the tail.
  static const double _releaseRate = 30.0;

  /// Snap band: inside it the quantized sigma already equals rest blur,
  /// so jumping to 1.0 is pixel-invisible.
  static const double settleBand = 0.015;

  static double targetScale(double pointerSpeedPx, [double morphSpeed = 0]) {
    const tokens = GlassTokens();
    final minScale = tokens.minMotionBlurSigma / tokens.blurSigma;
    final speed = pointerSpeedPx + morphSpeed * 900.0;
    final t = ((speed - _fullSpeed) / (_floorSpeed - _fullSpeed)).clamp(
      0.0,
      1.0,
    );
    return 1.0 - t * (1.0 - minScale);
  }

  static double approach({
    required double value,
    required double target,
    required double dt,
  }) {
    const tokens = GlassTokens();
    final minScale = tokens.minMotionBlurSigma / tokens.blurSigma;
    final rate = target < value ? _attackRate : _releaseRate;
    final next = value + (target - value) * (1 - math.exp(-dt * rate));
    if (target >= 1.0 && (1.0 - next).abs() < settleBand) {
      return 1.0;
    }
    return next.clamp(minScale, 1.0);
  }
}
