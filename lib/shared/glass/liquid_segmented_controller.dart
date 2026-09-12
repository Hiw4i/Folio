import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'glass_tokens.dart';

class LiquidSegmentedController extends ChangeNotifier {
  LiquidSegmentedController({
    required int initialIndex,
    required int itemCount,
    TickerProvider? vsync,
  }) : assert(itemCount > 0),
       assert(initialIndex >= 0 && initialIndex < itemCount),
       _itemCount = itemCount,
       position = initialIndex.toDouble(),
       _target = initialIndex.toDouble() {
    final ticker = vsync?.createTicker(_onTick);
    _ticker = ticker;
    ticker?.start();
  }

  static const double _fixedStep = 1 / 120;
  static const int _maxSubsteps = 4;
  static const SpringDescription _stretchSpring = SpringDescription(
    mass: 0.86,
    stiffness: 250,
    damping: 18,
  );

  final int _itemCount;
  Ticker? _ticker;
  MotionTokens _tokens = const MotionTokens.standard();
  Duration? _lastTick;
  double _accumulator = 0;
  double _target;
  bool _pointerDown = false;
  double _maximumStretch = 1;
  Offset _lightTarget = Offset.zero;

  double position;
  double velocity = 0;
  double stretch = 0;
  double stretchVelocity = 0;
  double press = 0;
  double pressVelocity = 0;
  Offset lightPosition = Offset.zero;

  int get targetIndex => _target.round();
  bool get isPointerDown => _pointerDown;

  void setReducedMotion(bool reduced) {
    final next = reduced
        ? const MotionTokens.reduced()
        : const MotionTokens.standard();
    final maximumStretch = reduced ? 0.08 : 1.0;
    if (_tokens.maxDrag == next.maxDrag && _maximumStretch == maximumStretch) {
      return;
    }
    _tokens = next;
    _maximumStretch = maximumStretch;
    stretch = math.min(stretch, maximumStretch);
    _wake();
    notifyListeners();
  }

  void select(int index) {
    assert(index >= 0 && index < _itemCount);
    final nextTarget = index.toDouble();
    if ((_target - nextTarget).abs() < 0.001 &&
        (position - nextTarget).abs() < 0.001) {
      return;
    }
    final travel = (nextTarget - position).abs();
    _target = nextTarget;
    if (_maximumStretch > 0.1) {
      stretchVelocity += math.min(7.5, 1.8 + travel * 1.15);
    }
    _wake();
    notifyListeners();
  }

  void beginPointer(Offset position) {
    _pointerDown = true;
    _lightTarget = position;
    _wake();
    notifyListeners();
  }

  void movePointer(Offset position) {
    _lightTarget = position;
    _wake();
  }

  void endPointer() {
    if (!_pointerDown) {
      return;
    }
    _pointerDown = false;
    _wake();
    notifyListeners();
  }

  @visibleForTesting
  void stepForTest(double seconds) {
    var remaining = seconds.clamp(0.0, 1.0);
    while (remaining > 0) {
      final step = math.min(_fixedStep, remaining);
      _step(step);
      remaining -= step;
    }
    notifyListeners();
  }

  void _wake() {
    _ticker?.muted = false;
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
    while (_accumulator >= _fixedStep && steps < _maxSubsteps) {
      _step(_fixedStep);
      _accumulator -= _fixedStep;
      steps++;
    }
    if (steps == _maxSubsteps) {
      _accumulator = math.min(_accumulator, _fixedStep);
    }
    notifyListeners();
    if (_isAtRest) {
      _ticker?.muted = true;
    }
  }

  bool get _isAtRest =>
      (position - _target).abs() < 0.001 &&
      velocity.abs() < 0.01 &&
      stretch < 0.002 &&
      stretchVelocity.abs() < 0.01 &&
      press < 0.002 &&
      pressVelocity.abs() < 0.01 &&
      (!_pointerDown && (lightPosition - _lightTarget).distance < 0.05);

  void _step(double dt) {
    final movement = _springScalar(
      position,
      velocity,
      _target,
      _tokens.separation,
      dt,
    );
    position = movement.$1.clamp(-0.08, _itemCount - 0.92);
    velocity = movement.$2;

    final distance = (_target - position).abs();
    final dynamicStretch =
        (distance * 0.34 + velocity.abs() * 0.055).clamp(0.0, 1.0) *
        _maximumStretch;
    final stretching = _springScalar(
      stretch,
      stretchVelocity,
      dynamicStretch,
      _stretchSpring,
      dt,
    );
    stretch = stretching.$1.clamp(0.0, _maximumStretch * 1.08);
    stretchVelocity = stretching.$2;

    final pressing = _springScalar(
      press,
      pressVelocity,
      _pointerDown ? 1 : 0,
      _tokens.press,
      dt,
    );
    press = pressing.$1.clamp(0.0, 1.08);
    pressVelocity = pressing.$2;
    lightPosition = Offset.lerp(
      lightPosition,
      _lightTarget,
      1 - math.exp(-dt * 22),
    )!;
  }

  static (double, double) _springScalar(
    double position,
    double velocity,
    double target,
    SpringDescription spring,
    double dt,
  ) {
    final acceleration =
        (spring.stiffness * (target - position) - spring.damping * velocity) /
        spring.mass;
    final nextVelocity = velocity + acceleration * dt;
    return (position + nextVelocity * dt, nextVelocity);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
